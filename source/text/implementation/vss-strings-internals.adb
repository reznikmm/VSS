--
--  Copyright (C) 2020-2024, AdaCore
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

package body VSS.Strings.Internals is

   --------------------------
   -- Data_Access_Constant --
   --------------------------

   function Data_Access_Constant
     (Self : VSS.Strings.Virtual_String'Class)
      return not null VSS.Strings.Internals.String_Data_Constant_Access is
   begin
      return Self.Data'Unchecked_Access;
   end Data_Access_Constant;

   -----------------
   -- Set_By_Move --
   -----------------

   procedure Set_By_Move
     (Self : in out VSS.Strings.Virtual_String'Class;
      To   : in out VSS.Implementation.Strings.String_Data) is
   begin
      VSS.Implementation.Strings.Unreference (Self.Data);
      Self.Data := To;
      To := (others => <>);
   end Set_By_Move;

   ----------------------------
   -- To_Magic_String_Access --
   ----------------------------

   function To_Magic_String_Access
     (Item : VSS.Implementation.Referrers.Virtual_String_Access)
      return VSS.Implementation.Referrers.Magic_String_Access is
   begin
      return VSS.Implementation.Referrers.Magic_String_Access (Item);
   end To_Magic_String_Access;

   -----------------------
   -- To_Virtual_String --
   -----------------------

   function To_Virtual_String
     (Item : in out VSS.Implementation.Strings.String_Data)
      return VSS.Strings.Virtual_String is
   begin
      return Result : VSS.Strings.Virtual_String do
         Result.Data := Item;

         VSS.Implementation.Strings.Reference (Result.Data);
      end return;
   end To_Virtual_String;

   ------------------------------
   -- To_Virtual_String_Access --
   ------------------------------

   function To_Virtual_String_Access
     (Item : VSS.Implementation.Referrers.Magic_String_Access)
      return VSS.Implementation.Referrers.Virtual_String_Access is
   begin
      return VSS.Implementation.Referrers.Virtual_String_Access (Item);
   end To_Virtual_String_Access;

end VSS.Strings.Internals;
