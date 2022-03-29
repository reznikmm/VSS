------------------------------------------------------------------------------
--                        M A G I C   R U N T I M E                         --
--                                                                          --
--                       Copyright (C) 2022, AdaCore                        --
--                                                                          --
-- This library is free software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License  as published by the Free --
-- Software  Foundation;  either version 3,  or (at your  option) any later --
-- version. This library is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE.                            --
--                                                                          --
-- As a special exception under Section 7 of GPL version 3, you are granted --
-- additional permissions described in the GCC Runtime Library Exception,   --
-- version 3.1, as published by the Free Software Foundation.               --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
------------------------------------------------------------------------------
--  Low level binding to Windows API (KERNEL32.DLL).

package VSS.Implementation.Windows.Kernel32 is

   pragma Linker_Options ("-lkernel32");

   function CloseHandle (hObject : HANDLE) return BOOL
     with Import, Convention => Stdcall, Link_Name => "CloseHandle";

   function GetCommandLine return LPWSTR
     with Import, Convention => Stdcall, Link_Name => "GetCommandLineW";

   function GetCurrentProcess return HANDLE
     with Import, Convention => Stdcall, Link_Name => "GetCurrentProcess";

   function GetLastError return DWORD
     with Import, Convention => Stdcall, Link_Name => "GetLastError";

   function GetEnvironmentVariable
     (lpName   : LPCWSTR;
      lpBuffer : LPWSTR;
      nSize    : DWORD) return DWORD
     with Import,
          Convention => Stdcall,
          Link_Name  => "GetEnvironmentVariableW";

   function GetTempPath
     (nBufferLength : DWORD;
      lpBuffer      : LPWSTR) return DWORD
      with Import, Convention => Stdcall, Link_Name => "GetTempPathW";

   function GetLongPathName
     (lpszShortPath : LPCWSTR;
      lpszLongPath  : LPWSTR;
      cchBuffer     : DWORD) return DWORD
      with Import, Convention => Stdcall, Link_Name => "GetLongPathNameW";

   procedure LocalFree (hMem : LPWSTR_Pointer)
     with Import, Convention => StdCall, Link_Name => "LocalFree";

end VSS.Implementation.Windows.Kernel32;
