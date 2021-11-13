## {$reference System.Drawing.dll}
uses System.Diagnostics, System.Drawing;

//var icon_file := System.IO.File.Create('Icon.ico');
//var icon_png := Bitmap.Create('icon.png');
//Icon.FromHandle(icon_png.GetHicon).Save(icon_file);
//icon_file.Close;

var psi := new ProcessStartInfo('ResGen\RC.exe', 'RM.rc');
psi.UseShellExecute := false;
var p := new Process;
p.StartInfo := psi;
p.Start;
p.WaitForExit;





;