--
--  Copyright (C) 2022-2023, AdaCore
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

--  Low level binding to Windows API (USERENV.DLL).

package VSS.Implementation.Windows.Userenv is

   pragma Linker_Options ("-luserenv");

   function GetUserProfileDirectory
     (hToken       : HANDLE;
      lpProfileDir : LPWSTR;
      lpcchSize    : in out DWORD)
      return BOOL
     with Import,
          Convention => Stdcall,
          External_Name  => "GetUserProfileDirectoryW";

end VSS.Implementation.Windows.Userenv;
