unit ExtAnalysis;

interface

function GetExecStr(fname: string): string;

implementation

uses System, System.Runtime.InteropServices;

{$region Win}

// https://stackoverflow.com/questions/162331/finding-the-default-application-for-opening-a-particular-file-type-on-windows
function AssocQueryString(
    flags, str_type: UInt32;
    pszAssoc, pszExtra: string;
    [Out] pszOut: StringBuilder;
    var pcchOut: UInt32
): UInt32;
external 'Shlwapi.dll';

function GetExecStrWin(fname: string): string;
const S_OK = 0;
const S_FALSE = 1;
const str_type = 1; // Shell command
begin
  var ext := System.IO.Path.GetExtension(fname);
  var lenght: UInt32 := 0;
  
  var ec := AssocQueryString(0, str_type, ext, 'open', nil, lenght);
  if ec <> S_FALSE then raise new System.InvalidOperationException($'Error code: {ec}');
  
  var sb := new StringBuilder(lenght);
  ec := AssocQueryString(0, str_type, ext, 'open', sb, lenght);
  if ec <> S_OK then raise new System.InvalidOperationException($'Error code: {ec}');
  
  Result := sb.ToString;
end;

{$endregion Win}

{$region Linux}

function GetExecStrLinux(fname: string): string;
//  function RunTakeRes(
begin
  
  raise new System.NotImplementedException;
  
end;

{$endregion Linux}

var f_GetExecStr: string->string;
function GetExecStr(fname: string) := f_GetExecStr(fname);

begin
  
  if RuntimeInformation.IsOSPlatform(OSPlatform.Windows) then
  begin
    
    if FileExists('Z:/usr/bin/linux64') then
      // wine
      f_GetExecStr := GetExecStrLinux else
      // regular win
      f_GetExecStr := GetExecStrWin;
    
  end else
  
  // WPF doesn't work with mono, so need to use wine anyway
//  if RuntimeInformation.IsOSPlatform(OSPlatform.Linux) then
//    f_GetExecStr := GetExecStrLinux else
  
    raise new NotSupportedException('Unsupported OS');
end.