## uses System, System.Runtime.InteropServices, PABCSystem;

(**
[Flags]
public enum AssocF
{
    None = 0,
    Init_NoRemapCLSID = 0x1,
    Init_ByExeName = 0x2,
    Open_ByExeName = 0x2,
    Init_DefaultToStar = 0x4,
    Init_DefaultToFolder = 0x8,
    NoUserSettings = 0x10,
    NoTruncate = 0x20,
    Verify = 0x40,
    RemapRunDll = 0x80,
    NoFixUps = 0x100,
    IgnoreBaseClass = 0x200,
    Init_IgnoreUnknown = 0x400,
    Init_Fixed_ProgId = 0x800,
    Is_Protocol = 0x1000,
    Init_For_File = 0x2000
}

public enum AssocStr
{
    Command = 1,
    Executable,
    FriendlyDocName,
    FriendlyAppName,
    NoOpen,
    ShellNewValue,
    DDECommand,
    DDEIfExec,
    DDEApplication,
    DDETopic,
    InfoTip,
    QuickTip,
    TileInfo,
    ContentType,
    DefaultIcon,
    ShellExtension,
    DropTarget,
    DelegateExecute,
    Supported_Uri_Protocols,
    ProgID,
    AppID,
    AppPublisher,
    AppIconReference,
    Max
}
(**)

function AssocQueryString(
    flags, str_type: UInt32;
    pszAssoc, pszExtra: string;
    [Out] pszOut: StringBuilder;
    var pcchOut: UInt32
): UInt32;
external 'Shlwapi.dll';

(**
  static string AssocQueryString(AssocStr association, string extension)
{
    const int S_OK = 0;
    const int S_FALSE = 1;

    uint length = 0;
    uint ret = AssocQueryString(AssocF.None, association, extension, null, null, ref length);
    if (ret != S_FALSE)
    {
        throw new InvalidOperationException("Could not determine associated string");
    }

    var sb = new StringBuilder((int)length); // (length-1) will probably work too as the marshaller adds null termination
    ret = AssocQueryString(AssocF.None, association, extension, null, sb, ref length);
    if (ret != S_OK)
    {
        throw new InvalidOperationException("Could not determine associated string"); 
    }

    return sb.ToString();
}
(**)
function GetExecStr(ext: string): string;
const S_OK = 0;
const S_FALSE = 1;
const str_type = 1; // Command
begin
  var lenght: UInt32 := 0;
  
  var ec := AssocQueryString(0, str_type, ext, nil, nil, lenght);
  if ec <> S_FALSE then raise new System.InvalidOperationException($'Error code: {ec}');
  
  var sb := new StringBuilder(lenght);
  ec := AssocQueryString(0, str_type, ext, nil, sb, lenght);
  if ec <> S_OK then raise new System.InvalidOperationException($'Error code: {ec}');
  
  Result := sb.ToString;
end;


//GetExecStr('.mp4').Println;
//exit;

var files := EnumerateAllFiles(ReadlnString).Where(fname->
begin
  Result := false;
  var ext := System.IO.Path.GetExtension(fname);
  if ext.Length=0 then exit;
  try
    var str := GetExecStr(ext);
    Result := str.ToLower.Contains('mpv');
    //if not Result then fname.Println;
  except
    on e: Exception do
    begin
      Writeln(fname);
      Writeln(e);
    end;
  end;
end).ToArray;
var c := files.Count;
try
  while true do
    System.Diagnostics.Process.Start(
      files.ElementAt(Random(c)
    )).WaitForExit;
except
  on e: Exception do
  begin
    Writeln(e);
    Readln;
  end;
end;