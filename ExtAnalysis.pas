unit ExtAnalysis;

interface

function GetExecStr(ext: string): string;

implementation

uses System, System.Runtime.InteropServices;

// https://stackoverflow.com/questions/162331/finding-the-default-application-for-opening-a-particular-file-type-on-windows
function AssocQueryString(
    flags, str_type: UInt32;
    pszAssoc, pszExtra: string;
    [Out] pszOut: StringBuilder;
    var pcchOut: UInt32
): UInt32;
external 'Shlwapi.dll';

function GetExecStr(ext: string): string;
const S_OK = 0;
const S_FALSE = 1;
const str_type = 1; // Shell command
begin
  var lenght: UInt32 := 0;
  
  var ec := AssocQueryString(0, str_type, ext, nil, nil, lenght);
  if ec <> S_FALSE then raise new System.InvalidOperationException($'Error code: {ec}');
  
  var sb := new StringBuilder(lenght);
  ec := AssocQueryString(0, str_type, ext, nil, sb, lenght);
  if ec <> S_OK then raise new System.InvalidOperationException($'Error code: {ec}');
  
  Result := sb.ToString;
end;

end.