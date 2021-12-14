{$mainresource 'RM.res'}

{$reference PresentationFramework.dll}
{$reference PresentationCore.dll}
{$reference WindowsBase.dll}
{$apptype windows}

{$region TODO}

//TODO Папка должно в ref содержать все свои файлы, даже если обратного ref небыло
// - Тогда будет нормально работать увеличение частоты при тыке
// - А ещё можно будет не делать словарь папок-визуализаций

//TODO Не пересоздавать всё визуальное дерево
// - Если кинули C:/A ; C:/A/B/C ; C:/A/B
// --- Тогда надо будет вставить промежуточную папку в визуальное дерево
// - То же самое если C:/A/B/C ; C:/A/B ; C:/A
// --- Только теперь заменя идёт между root и его первой дочеренной папкой

{$endregion TODO}

uses System;
uses System.Windows;
uses System.Windows.Media;
uses System.Windows.Controls;
uses PABCSystem;

uses ExtAnalysis;

type
  
  {$region BackEnd}
  
  {$region WeightedData}
  
  WeightedPath = sealed partial class
    weight: integer? := nil;
  end;
  WeightedFile = sealed partial class
    weight: integer? := 1;
  end;
  
  WeightedPath = sealed partial class
    static All := new Dictionary<string, WeightedPath>;
    path: string;
    ref := new HashSet<WeightedFile>;
    
    display_content := false;
    
    constructor(path: string) := self.path := path;
    
    static function FromPath(path: string): WeightedPath;
    begin
      if All.TryGetValue(path, Result) then exit;
      Result := new WeightedPath(path);
      All[path] := Result;
    end;
    
    function GetWeight: integer;
    begin
      if weight=nil then
        weight := ref.Min(f->f.weight.Value);
      Result := weight.Value;
    end;
    
    procedure AddRef(f: WeightedFile);
    begin
      self.weight := nil;
      self.ref += f;
    end;
    
    procedure RemoveRef(f: WeightedFile);
    begin
      if not self.ref.Remove(f) then raise new System.InvalidOperationException;
      self.weight := nil;
      if self.ref.Count<>0 then exit;
      WeightedPath.All.Remove(self.path);
    end;
    
  end;
  WeightedFile = sealed partial class
    base_path, fname: string;
    ref: array of WeightedPath;
    
    constructor(base_path, fname: string);
    begin
      self.base_path := base_path;
      self.fname := fname;
      var paths := fname.Substring(base_path.Length).Split('\')[1:^1];
      var ref_sb := new StringBuilder(fname.Length);
      ref_sb += base_path;
      ref_sb += '\';
      ref := ArrGen(paths.Length, i->
      begin
        ref_sb += paths[i];
        ref_sb += '\';
        Result := WeightedPath.FromPath(ref_sb.ToString);
        Result.AddRef(self);
      end);
    end;
    
    procedure Remove;
    begin
      foreach var p in self.ref do
        p.RemoveRef(self);
      weight := nil;
    end;
    
    procedure UpdateWeight(delta: integer);
    begin
      self.weight := (self.weight.Value + delta).Clamp(0,999);
      if weight=0 then
        self.Remove else
      foreach var p in ref do
        p.weight := nil;
    end;
    
  end;
  
  {$endregion WeightedData}
  
  {$region FileList}
  
  FileListNode = sealed class
    private prev, next: FileListNode;
    public f: WeightedFile;
    
    public constructor(f: WeightedFile := nil);
    begin
      self.prev := self;
      self.next := self;
      self.f := f;
    end;
    public constructor(prev, next: FileListNode; f: WeightedFile);
    begin
      self.prev := prev; prev.next := self;
      self.next := next; next.prev := self;
      self.f := f;
    end;
    
    public function Insert(f: WeightedFile): FileListNode;
    begin
      foreach var prev in self.Enmr do
      begin
        var next := prev.Enmr.Skip(1).FirstOrDefault ?? prev;
        if prev.f.fname = f.fname then
        begin
          f.UpdateWeight(prev.f.weight.Value);
          prev.Remove;
          
          Result := if next=prev then
            new FileListNode(f) else
            new FileListNode(next.prev, next, f);
          prev.next := Result;
          
          exit;
        end;
//        var v1 := prev.f.fname < next.f.fname;
//        var v2 := prev.f.fname < f.fname;
//        var v3 := f.fname < next.f.fname;
        if prev.f.fname < next.f.fname
          ? (prev.f.fname < f.fname) and (f.fname < next.f.fname)
          : (prev.f.fname < f.fname) or (f.fname < next.f.fname)
          then
        begin
          Result := new FileListNode(prev, next, f);
          exit;
        end;
      end;
      if not self.IsRemoved then raise new System.InvalidOperationException;
      Result := new FileListNode(f);
      self.next := Result;
    end;
    
    //TODO #2561
    public function IsRemoved: boolean := (f=nil) or (f.weight=nil);
    
    public function Enmr: sequence of FileListNode;
    begin
      
      var curr := self;
      begin
        var prev := new HashSet<FileListNode>(|self|);
        while curr.IsRemoved do
        begin
          curr := curr.next;
          if not prev.Add(curr) then exit;
        end;
      end;
      
      var first := curr;
      repeat
        if not curr.IsRemoved then
          yield curr;
        curr := curr.next;
      until curr=first;
      
    end;
    
    public procedure Remove;
    begin
      prev.next := self.next;
      next.prev := self.prev;
      f.Remove;
      f := nil;
    end;
    
  end;
  
  {$endregion FileList}
  
  BoolValue = sealed class
    public val: boolean;
    public constructor(val: boolean) := self.val := val;
    private constructor := raise new System.InvalidOperationException;
  end;
  RM = static class
    public static files := new FileListNode;
    public static files_lock := new object;
    public static event FilesUpdated: ()->();
    public static event WeightsUpdated: ()->();
    
    public static cycle := new BoolValue(false);
    public static choose_rng := new BoolValue(true);
    
    public static event FileSwitch: string->();
    private static procedure InvokeFileSwitch(name: string);
    begin
      var FileSwitch := RM.FileSwitch;
      if FileSwitch<>nil then FileSwitch(name);
    end;
    
    public static procedure SaveRMData(str: System.IO.Stream);
    begin
      var bw := new System.IO.BinaryWriter(str);
      foreach var n in files.Enmr do
      begin
        var f := n.f;
        bw.Write(f.base_path);
        bw.Write(f.fname.SubString(f.base_path.Length));
        bw.Write(f.weight.Value);
      end;
      bw.Close;
    end;
    public static procedure LoadRMData(str: System.IO.Stream);
    begin
      var br := new System.IO.BinaryReader(str);
      var last := files;
      while br.BaseStream.Position<br.BaseStream.Length do
      begin
        var base_path := br.ReadString;
        var f := new WeightedFile(base_path, base_path+br.ReadString);
        f.weight := br.ReadInt32;
        lock RM.files_lock do
          last := last.Insert(f);
      end;
      br.Close;
      FilesUpdated;
    end;
    
    private static function CheckExt(ext: string): boolean;
    begin
      Result := false;
      if ext in |'.db', '.lnk', ''| then exit;
      try
        Result := GetExecStr(ext).Contains('\mpv.exe');
      except
        on e: Exception do
          MessageBox.Show(e.ToString, ext);
      end;
    end;
    public static procedure AddName(name: string) :=
    if System.IO.File.Exists(name) then
    begin
      name := name.Replace('/','\');
      var ext := System.IO.Path.GetExtension(name);
      
      if ext.ToUpper = '.RMData'.ToUpper then
      begin
        LoadRMData(System.IO.File.OpenRead(name));
        exit;
      end;
      
      if not CheckExt(ext) then exit;
      lock files_lock do
        files.Insert(new WeightedFile(System.IO.Path.GetDirectoryName(name), name));
      
      FilesUpdated;
    end else
    if System.IO.Directory.Exists(name) then
    begin
      name := name.Replace('/','\');
      var prev := files;
      var base_dir := System.IO.Path.GetDirectoryName(name.TrimEnd('\')).TrimEnd('\');
      foreach var fname in EnumerateAllFiles(name) do
      begin
        if not CheckExt(System.IO.Path.GetExtension(fname)) then continue;
        lock files_lock do
          prev := prev.Insert(new WeightedFile(base_dir, fname));
      end;
      
      FilesUpdated;
    end else
      MessageBox.Show(name, 'Value not recognized as file/folder');
    
    static procedure StartPlaying := System.Threading.Thread.Create(()->
    begin
      {$reference System.Speech.dll}
      var speaker := new System.Speech.Synthesis.SpeechSynthesizer;
      speaker.SetOutputToDefaultAudioDevice;
      
      while true do
      try
        var files: array of FileListNode;
        lock files_lock do files := RM.files.Enmr.ToArray;
        
        if files.Length=0 then
        begin
          Sleep(100);
          continue;
        end;
        
        var curr := default(FileListNode);
        if cycle.val then
          curr := files[0] else
        begin
          if not choose_rng.val then
          begin
            curr := if files[0]=RM.files then
              files[1] else files[0];
          end else
          begin
            var weight := Random(files.Sum(n->n.f.weight.Value));
            foreach var n in files do
            begin
              if n.f.weight.Value > weight then
              begin
                curr := n;
                break;
              end;
              weight -= n.f.weight.Value;
            end;
          end;
        end;
        RM.files := curr;
        
        var full_fname := curr.f.fname;
        var base_path := curr.f.base_path;
        var fname := full_fname.SubString(base_path.Length+1);
        
        InvokeFileSwitch(fname);
        speaker.Speak(System.IO.Path.ChangeExtension(fname,nil).Replace('\', ' - '));
        
        PlayFile(full_fname);
        InvokeFileSwitch('%Switching%');
        
      except
        on e: Exception do
        begin
          System.Media.SystemSounds.Exclamation.Play;
          MessageBox.Show(e.ToString);
        end;
      end;
      
    end).Start;
    
    static procedure PlayFile(fname: string);
    begin
      
      var executable := GetExecStr(System.IO.Path.GetExtension(fname)).Remove(' "%1"').Remove('"');
      var args := $'"{fname}" "--window-minimized=yes"';
      var proc := System.Diagnostics.Process.Start(executable, args);
      proc.WaitForExit;
      case proc.ExitCode of
        0: exit;
        1: MessageBox.Show('Error initializing mpv. This is also returned if unknown options are passed to mpv.');
        2: MessageBox.Show('The file passed to mpv couldn''t be played. This is somewhat fuzzy: currently, playback of a file is considered to be successful if initialization was mostly successful, even if playback fails immediately after initialization.');
        3: MessageBox.Show('There were some files that could be played, and some files which couldn''t (using the definition of success from above).');
        4: MessageBox.Show('Quit due to a signal, Ctrl+c in a VO window (by default), or from the default quit key bindings in encoding mode.');
        else MessageBox.Show($'MPV error code: {proc.ExitCode}');
      end;
      
    end;
    
  end;
  
  {$endregion BackEnd}
  
  {$region FrontEnd}
  
  {$region Bool Button's}
  
  ButtonSwitch = abstract class(Button)
    
    protected const ContentSize = 32;
    protected procedure BuildContent(c: Canvas); abstract;
    
    public constructor(source: BoolValue);
    begin
      
      var c := new Canvas;
      self.Content := c;
      c.Width := ContentSize;
      c.Height := ContentSize;
      BuildContent(c);
      
      var SetState := procedure->
      begin
        c.Background := if source.val then
          new SolidColorBrush(Color.FromArgb(128,255,0,0)) else
          Brushes.Transparent;
      end;
      SetState;
      
      self.Click += (o,e)->
      begin
        source.val := not source.val;
        SetState;
        e.Handled := true;
      end;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
  CycleButton = sealed class(ButtonSwitch)
    
    public constructor :=
    inherited Create(RM.cycle);
    
    protected procedure BuildContent(c: Canvas); override;
    begin
      
      var circle := new System.Windows.Shapes.Ellipse;
      c.Children.Add(circle);
      circle.Width := ContentSize*0.70;
      circle.Height := ContentSize*0.70;
      Canvas.SetLeft(circle, ContentSize*0.15);
      Canvas.SetTop(circle, ContentSize*0.15);
      circle.Stroke := Brushes.Black;
      
      begin
        var l := new System.Windows.Shapes.Line;
        c.Children.Add(l);
        l.X1 := ContentSize*0.00; l.Y1 := ContentSize*0.40;
        l.X2 := ContentSize*0.15; l.Y2 := ContentSize*0.60;
        l.Stroke := Brushes.Black;
      end;
      
      begin
        var l := new System.Windows.Shapes.Line;
        c.Children.Add(l);
        l.X1 := ContentSize*0.30; l.Y1 := ContentSize*0.40;
        l.X2 := ContentSize*0.15; l.Y2 := ContentSize*0.60;
        l.Stroke := Brushes.Black;
      end;
      
      begin
        var l := new System.Windows.Shapes.Line;
        c.Children.Add(l);
        l.X1 := ContentSize*1.00; l.Y1 := ContentSize*0.60;
        l.X2 := ContentSize*0.85; l.Y2 := ContentSize*0.40;
        l.Stroke := Brushes.Black;
      end;
      
      begin
        var l := new System.Windows.Shapes.Line;
        c.Children.Add(l);
        l.X1 := ContentSize*0.70; l.Y1 := ContentSize*0.60;
        l.X2 := ContentSize*0.85; l.Y2 := ContentSize*0.40;
        l.Stroke := Brushes.Black;
      end;
      
    end;
    
  end;
  
  RngButton = sealed class(ButtonSwitch)
    
    public constructor :=
    inherited Create(RM.choose_rng);
    
    protected procedure BuildContent(c: Canvas); override;
    begin
      
      begin
        var p := new System.Windows.Shapes.Path;
        c.Children.Add(p);
        p.Data := new PathGeometry(|new PathFigure(
          new Point(ContentSize*0.00,ContentSize*0.80), new PathSegment[](
            new PolyBezierSegment(|
              new Point(ContentSize*0.50, ContentSize*0.80),
              new Point(ContentSize*0.50, ContentSize*0.20),
              new Point(ContentSize*1.00, ContentSize*0.20)
            |, true)
          ), false
        )|);
        p.Stroke := Brushes.Black;
      end;
      
      begin
        var p := new System.Windows.Shapes.Path;
        c.Children.Add(p);
        p.Data := new PathGeometry(|new PathFigure(
          new Point(ContentSize*0.00,ContentSize*0.20), new PathSegment[](
            new PolyBezierSegment(|
              new Point(ContentSize*0.50, ContentSize*0.20),
              new Point(ContentSize*0.50, ContentSize*0.80),
              new Point(ContentSize*1.00, ContentSize*0.80)
            |, true)
          ), false
        )|);
        p.Stroke := Brushes.Black;
      end;
      
    end;
    
  end;
  
  {$endregion Bool Button's}
  
  {$region Other Button's}
  
  SaveButton = sealed class(Button)
    
    public constructor;
    begin
      
      var im := new Image;
      self.Content := im;
      im.Width := ButtonSwitch.ContentSize;
      im.Height := ButtonSwitch.ContentSize;
      {$resource 'save.png'}
      im.Source := System.Windows.Media.Imaging.BitmapFrame.Create(GetResourceStream('save.png'));
      
      self.Click += (o,e)->
      begin
        var d := new Microsoft.Win32.SaveFileDialog;
        d.DefaultExt := '.RMData';
        d.Filter := 'RM Save data|*.RMData|All files|*';
        d.InitialDirectory := GetCurrentDir;
        var res := d.ShowDialog; //TODO #2562
        if true <> res then exit;
        RM.SaveRMData(d.OpenFile);
      end;
      
    end;
    
  end;
  
  LoadButton = sealed class(Button)
    
    public constructor;
    begin
      
      var im := new Image;
      self.Content := im;
      im.Width := ButtonSwitch.ContentSize;
      im.Height := ButtonSwitch.ContentSize;
      {$resource 'load.png'}
      im.Source := System.Windows.Media.Imaging.BitmapFrame.Create(GetResourceStream('load.png'));
      
      self.Click += (o,e)->
      begin
        var d := new Microsoft.Win32.OpenFileDialog;
        d.DefaultExt := '.RMData';
        d.Filter := 'RM Save data|*.RMData|All files|*';
        d.InitialDirectory := GetCurrentDir;
        var res := d.ShowDialog; //TODO #2562
        if true <> res then exit;
        RM.LoadRMData(d.OpenFile);
      end;
      
    end;
    
  end;
  
  {$endregion Other Button's}
  
  {$region FileDisplay}
  
  DisplayHeader = sealed class(StackPanel)
    private char_set: string;
    private char_box := new TextBlock;
    private weight_box := new TextBlock;
    
    public event WeightChanged: integer->();
    public event ResetRequested: ()->();
    
    public constructor(char_set: string; name: string);
    begin
      self.char_set := char_set;
      self.Orientation := System.Windows.Controls.Orientation.Horizontal;
      
      self.Children.Add(char_box);
      char_box.Width := 16;
      
      var weight_box_b := new Border;
      self.Children.Add(weight_box_b);
      weight_box_b.BorderBrush := Brushes.Black;
      weight_box_b.BorderThickness := new Thickness(1);
      weight_box_b.Margin := new Thickness(0,0,5,0);
      
      weight_box_b.Child := weight_box;
      weight_box.Margin := new Thickness(2,0,2,0);
      weight_box.MouseUp += (o,e)->
      begin
        var delta: integer;
        case e.ChangedButton of
          System.Windows.Input.MouseButton.Left: delta := +1;
          System.Windows.Input.MouseButton.Right: delta := -1;
          else exit;
        end;
        if System.Windows.Input.Keyboard.IsKeyDown(System.Windows.Input.Key.LeftShift) then
          delta *= 10;
        if System.Windows.Input.Keyboard.IsKeyDown(System.Windows.Input.Key.LeftCtrl) then
          delta *= 100;
        WeightChanged(delta);
        e.Handled := true;
      end;
      
      var reset_button := new Button;
      self.Children.Insert(2, reset_button);
      reset_button.Width := 16;
      reset_button.Height := 16;
      reset_button.Margin := new Thickness(0,0,5,0);
      reset_button.Click += (o,e)->ResetRequested();
      
      var reset_button_im := new System.Windows.Shapes.Rectangle;
      reset_button.Content := reset_button_im;
      reset_button_im.Width := 7;
      reset_button_im.Height := 7;
      reset_button_im.Fill := Brushes.Red;
      
      var body_title := new TextBlock;
      self.Children.Add(body_title);
      //TODO Если поменять parent_path - это не обновится
      // - Но пока всё дерево пересоздаётся - не важно
      body_title.Text := name;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public procedure UpdateChar(ind: integer) :=
    char_box.Text := char_set[ind+1];
    
    public procedure UpdateWeight(w: integer) :=
    weight_box.Text := w.ToString('D3');
    
  end;
  
  FileDisplay = sealed class(ContentControl)
    private parent_path: string;
    private f: WeightedFile;
    
    private header: DisplayHeader;
    
    public constructor(parent_path: string; f: WeightedFile);
    begin
      self.parent_path := parent_path;
      self.f := f;
      
      header := new DisplayHeader('•', f.fname.SubString(parent_path.Length));
      self.Content := header;
      header.UpdateChar(0);
      header.UpdateWeight(f.weight.Value);
      header.WeightChanged += delta->
      begin
        f.UpdateWeight(delta);
        if f.weight=nil then
          RM.FilesUpdated else
          RM.WeightsUpdated;
      end;
      header.ResetRequested += ()->
      begin
        f.UpdateWeight(-f.weight.Value+1);
        RM.WeightsUpdated;
      end;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public procedure UpdateWeights :=
    header.UpdateWeight(f.weight.Value);
    
  end;
  
  FolderDisplay = sealed class(StackPanel)
    private parent_path: string;
    private path: WeightedPath;
    public sub_dirs := new Dictionary<string, FolderDisplay>;
    public files := new Dictionary<string, FileDisplay>;
    
    private title_bar: DisplayHeader;
    private dirs_panel := new StackPanel;
    private files_panel := new StackPanel;
    
    public constructor(parent_path: string; path: WeightedPath);
    begin
      self.parent_path := parent_path;
      self.path := path;
      
      var UpdateBodyShown: procedure;
      
      if parent_path<>nil then
      begin
        //TODO Если поменять parent_path - это не обновится
        title_bar := new DisplayHeader('►▼', path.path.SubString(parent_path.Length).TrimEnd('\'));
        self.Children.Add(title_bar);
        title_bar.UpdateWeight(path.GetWeight);
        title_bar.WeightChanged += delta->
        begin
          var full_update := false;
          var weight_update := false;
          foreach var f in path.ref.ToArray do
          begin
            f.UpdateWeight(delta);
            if f.weight=nil then
              full_update := true else
              weight_update := true;
          end;
          if full_update then
            RM.FilesUpdated else
          if weight_update then
            RM.WeightsUpdated else
            raise new System.InvalidOperationException;
        end;
        
        title_bar.ResetRequested += ()->
        begin
          foreach var f in path.ref.ToArray do
            f.UpdateWeight(-f.weight.Value+1);
          RM.WeightsUpdated;
        end;
        
        title_bar.MouseUp += (o,e)->
        begin
          path.display_content := not path.display_content;
          UpdateBodyShown;
        end;
        UpdateBodyShown += ()->title_bar.UpdateChar(ord(path.display_content));
        
      end;
      
      var body := new Border;
      self.Children.Add(body);
      body.Margin := new Thickness(5,0,0,0);
      
      if parent_path<>nil then
      begin
        body.BorderBrush := Brushes.Black;
        body.BorderThickness := new Thickness(1,0,0,0);
      end;
      
      var body_sp := new StackPanel;
      body.Child := body_sp;
      body_sp.Margin := new Thickness(8,0,0,0);
      
      body_sp.Children.Add(dirs_panel);
      body_sp.Children.Add(files_panel);
      
      UpdateBodyShown += ()->(
        body.Visibility := if path.display_content then
          System.Windows.Visibility.Visible else
          System.Windows.Visibility.Collapsed
      );
      UpdateBodyShown;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
    public function AddFolder(sub_path: WeightedPath): FolderDisplay;
    begin
      foreach var key in sub_dirs.Keys do
        if sub_path.path.StartsWith(System.IO.Path.Combine(self.path.path, key)) then
        begin
          Result := sub_dirs[key].AddFolder(sub_path);
          exit;
        end;
      Result := new FolderDisplay(self.path.path, sub_path);
      sub_dirs.Add(sub_path.path.SubString(self.path.path.Length), Result);
      dirs_panel.Children.Add(Result);
    end;
    
    public procedure AddFile(sub_file: WeightedFile);
    begin
      foreach var sub_display in sub_dirs.Values do
        if sub_display.path in sub_file.ref then
        begin
          sub_display.AddFile(sub_file);
          exit;
        end;
      var sub_display := new FileDisplay(self.path.path, sub_file);
      files.Add(sub_file.fname.SubString(self.path.path.Length), sub_display);
      files_panel.Children.Add(sub_display);
    end;
    
    public procedure UpdateWeights;
    begin
      if title_bar<>nil then
        title_bar.UpdateWeight(path.GetWeight);
      foreach var sub_dir in sub_dirs.Values do
        sub_dir.UpdateWeights;
      foreach var f in files.Values do
        f.UpdateWeights;
    end;
    
  end;
  
  FileDisplayContainer = sealed class(ScrollViewer)
    
    public constructor;
    begin
      self.VerticalScrollBarVisibility := ScrollBarVisibility.Auto;
      
      var root_path := new WeightedPath('');
      root_path.display_content := true;
      var root_display := new FolderDisplay(nil, root_path);
      self.Content := root_display;
      
      var TODO := 0; //TODO Полное пересоздание - да ещё и на каждый .AddName
      RM.FilesUpdated += ()->
      begin
        var files: array of WeightedFile;
        lock RM.files_lock do files := RM.files.Enmr.Select(n->n.f).ToArray;
        var paths := files.SelectMany(f->f.ref).ToHashSet;
        
//        WeightedPath.All.Values.PrintLines(p->p.path);
//        files.PrintLines(f->f.fname);
//        files.PrintLines(f->_ObjectToString(f.weight));
//        Writeln('='*30);
//        Sleep(100);
        
        root_display.sub_dirs.Clear;
        root_display.files.Clear;
        
        root_display.dirs_panel.Children.Clear;
        root_display.files_panel.Children.Clear;
        
        var paths_display := new Dictionary<WeightedPath, FolderDisplay>;
        paths_display.Add(root_path, root_display);
        foreach var path in paths.OrderBy(p->p.path) do
          paths_display.Add(path, root_display.AddFolder(path));
        
        foreach var f in files.OrderBy(f->f.fname) do
          paths_display[f.ref.FirstOrDefault??root_path].AddFile(f);
        
      end;
      
      RM.WeightsUpdated += ()->root_display.UpdateWeights();
      
    end;
    
  end;
  
  {$endregion FileDisplay}
  
  {$endregion FrontEnd}
  
begin
  var MainWindow := new Window;
  
  var dp := new DockPanel;
  MainWindow.Content := dp;
  
  var settings_panel := new StackPanel;
  dp.Children.Add(settings_panel);
  DockPanel.SetDock(settings_panel, Dock.Bottom);
  settings_panel.Orientation := Orientation.Horizontal;
  settings_panel.Children.Add(new CycleButton);
  settings_panel.Children.Add(new RngButton);
  settings_panel.Children.Add(new SaveButton);
  settings_panel.Children.Add(new LoadButton);
  
  var files_display := new FileDisplayContainer;
  dp.Children.Add(files_display);
  
  MainWindow.AllowDrop := true;
  MainWindow.DragOver += (o,e)->
  begin
    e.Effects := if e.Data.GetDataPresent('FileNameW') then
      DragDropEffects.Link else
      DragDropEffects.None;
    e.Handled := true;
  end;
  MainWindow.Drop += (o,e)->
  lock RM.files_lock do
  begin
    if not System.Windows.Input.Keyboard.IsKeyDown(System.Windows.Input.Key.LeftShift) then
      foreach var n in RM.files.Enmr do
        n.f.Remove;
    
    foreach var name in e.Data.GetData('FileDrop') as array of string do
      RM.AddName(name);
    
    e.Handled := true;
  end;
  
  foreach var arg in CommandLineArgs do
    RM.AddName(arg);
  
//  RM.AddName('C:\0Music\2Special\Perturbator\The Uncanny Valley\Neo Tokyo.mp4');
//  RM.AddName('C:\0Music\2Special\Perturbator\The Uncanny Valley\');
//  RM.AddName('C:\0Music\2Special\Perturbator\The Uncanny Valley');
//  RM.AddName('C:\0Music\0Misc');
//  RM.AddName('C:\0Music');
  
//  RM.AddName('C:\0Music\2Special\Rob Gasser\to sort\[20210815] Rob Gasser - Pieces.mp4');
//  RM.AddName('C:\0Music\2Special\Rob Gasser\to sort');
//  RM.AddName('C:\0Music\2Special\Rob Gasser');

//  RM.AddName('C:\0Music\2Special\Perturbator\The Uncanny Valley');
//  RM.files.Enmr.First.f.Remove;
//  RM.AddName('C:\0Music\2Special\Perturbator\The Uncanny Valley');
  
  RM.FileSwitch += fname->MainWindow.Dispatcher.Invoke(()->(MainWindow.Title := fname));
  RM.StartPlaying;
  
  Halt(Application.Create.Run(MainWindow));
end.