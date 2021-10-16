

{$reference PresentationFramework.dll}
{$reference PresentationCore.dll}
{$reference WindowsBase.dll}
{$apptype windows}

uses System;
uses System.Windows;
uses System.Windows.Controls;
uses PABCSystem;

uses ExtAnalysis;

type
  ButtonSwitch = sealed class(Button)
    public state := false;
    
    public constructor(im1, im2: string);
    begin
      
      var im := new Image;
      self.Content := im;
      
      var ims1 := System.Windows.Media.Imaging.BitmapFrame.Create(GetResourceStream(im1));
      var ims2 := System.Windows.Media.Imaging.BitmapFrame.Create(GetResourceStream(im2));
      
      im.Source := ims1;
      self.Click += (o,e)->
      begin
        state := not state;
        im.Source := state ? ims2 : ims1;
      end;
      
    end;
    private constructor := raise new System.InvalidOperationException;
    
  end;
  
begin
  var MainWindow := new Window;
//  AllocConsole;
  
  var g := new Grid;
  MainWindow.Content := g;
  g.ColumnDefinitions.Add(new ColumnDefinition);
  g.ColumnDefinitions.Add(new ColumnDefinition);
  
  {$resource im_cycle1.bmp}
  {$resource im_cycle2.bmp}
  var b1 := new ButtonSwitch('im_cycle1.bmp', 'im_cycle2.bmp');
  g.Children.Add(b1);
  Grid.SetColumn(b1, 0);
  
  {$resource im_random1.bmp}
  {$resource im_random2.bmp}
  var b2 := new ButtonSwitch('im_random1.bmp', 'im_random2.bmp');
  g.Children.Add(b2);
  Grid.SetColumn(b2, 1);
  
  var active_files := new string[0];
  var set_active_files := procedure(names: sequence of string)->
  begin
    var files := new List<string>;
    foreach var name in names do
      if System.IO.File.Exists(name) then
        files += name else
        files.AddRange(EnumerateAllFiles(name));
    files.RemoveAll(fname->
    try
      Result := false;
      var ext := System.IO.Path.GetExtension(fname);
      if ext in |'.db'| then exit;
      Result := not GetExecStr(ext).Contains('\mpv.exe');
    except
      on e: Exception do
      begin
        MessageBox.Show(e.ToString, fname);
        Result := true;
      end;
    end);
//    MessageBox.Show(System.Windows.Input.Keyboard.IsKeyDown(System.Windows.Input.Key.LeftShift).ToString);
    if System.Windows.Input.Keyboard.IsKeyDown(System.Windows.Input.Key.LeftShift) then
      active_files := active_files + files.ToArray else
      active_files := files.ToArray;
//    MessageBox.Show(active_files.JoinToString(#10));
  end;
  set_active_files(CommandLineArgs.Where(fname->System.IO.Directory.Exists(fname) or System.IO.File.Exists(fname)));
  
  MainWindow.AllowDrop := true;
  MainWindow.DragOver += (o,e)->
  begin
    if not e.Data.GetDataPresent('FileNameW') then
    begin
      e.Effects := DragDropEffects.None;
    end else
      e.Effects := DragDropEffects.Link;
    e.Handled := true;
  end;
  MainWindow.Drop += (o,e)->
  begin
    set_active_files(e.Data.GetData('FileDrop') as array of string);
    e.Handled := true;
  end;
  
  System.Threading.Thread.Create(()->
  begin
    var last_id := -1;
    
    {$reference System.Speech.dll}
    var speaker := new System.Speech.Synthesis.SpeechSynthesizer;
    speaker.SetOutputToDefaultAudioDevice;
    
    while true do
    try
      var files := active_files.ToArray;
      
      if files.Length=0 then
      begin
        Sleep(10);
        continue;
      end;
      
      var curr_id: integer;
      if b1.state then
        curr_id := last_id else
      if b2.state then
        curr_id := (last_id+1) mod files.Length else
        curr_id := Random(files.Length);
      curr_id := curr_id.Clamp(0, files.Length-1);
      last_id := curr_id;
      
      var fname := files[curr_id];
      MainWindow.Dispatcher.Invoke(()->begin MainWindow.Title := fname end);
      speaker.Speak(System.IO.Path.GetFileNameWithoutExtension(fname));
      
      var executable := GetExecStr(System.IO.Path.GetExtension(fname)).Remove(' "%1"').Remove('"');
      var args := $'"{fname}" "--window-minimized=yes"';
      var proc := System.Diagnostics.Process.Start(executable, args);
      proc.WaitForExit;
      MainWindow.Dispatcher.Invoke(()->begin MainWindow.Title := '%Switching%' end);
      case proc.ExitCode of
        0: continue;
        1: MessageBox.Show('Error initializing mpv. This is also returned if unknown options are passed to mpv.');
        2: MessageBox.Show('The file passed to mpv couldn''t be played. This is somewhat fuzzy: currently, playback of a file is considered to be successful if initialization was mostly successful, even if playback fails immediately after initialization.');
        3: MessageBox.Show('There were some files that could be played, and some files which couldn''t (using the definition of success from above).');
        4: MessageBox.Show('Quit due to a signal, Ctrl+c in a VO window (by default), or from the default quit key bindings in encoding mode.');
        else MessageBox.Show($'MPV error code: {proc.ExitCode}');
      end;
      
    except
      on e: Exception do
      begin
        System.Media.SystemSounds.Exclamation.Play;
        MessageBox.Show(e.ToString);
      end;
    end;
    
  end).Start;
  
  Halt(Application.Create.Run(MainWindow));
end.