

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
    var names := e.Data.GetData('FileDrop') as array of string;
    var files := new List<string>;
    foreach var name in names do
      if System.IO.File.Exists(name) then
        files += name else
        files.AddRange(EnumerateAllFiles(name));
    files.Count.Println;
    files.RemoveAll(fname->
    try
      Result := not GetExecStr(System.IO.Path.GetExtension(fname)).Contains('\mpv.exe');
    except
      on e: Exception do
      begin
        Writeln(fname);
        Writeln(e);
        Result := true;
      end;
    end);
    active_files := files.ToArray;
    e.Handled := true;
  end;
  
  System.Threading.Thread.Create(()->
  begin
    var last_id := -1;
    
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
      curr_id.Clamp(0, files.Length-1);
      last_id := curr_id;
      
      System.Diagnostics.Process.Start(
        files[curr_id]
      ).WaitForExit;
      
    except
      on e: Exception do
      begin
        Writeln(e);
        System.Media.SystemSounds.Exclamation.Play;
        Readln;
      end;
    end;
    
  end).Start;
  
  Halt(Application.Create.Run(MainWindow));
end.