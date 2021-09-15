------------------------------------------------------------------------------
--                        M A G I C   R U N T I M E                         --
--                                                                          --
--                     Copyright (C) 2020-2021, AdaCore                     --
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
--  Generic implementation of the string which use UTF-8 encoding for data.

with Ada.Unchecked_Deallocation;

with VSS.Implementation.Line_Iterators;
with VSS.Implementation.String_Configuration;
with VSS.Implementation.UCD_Casing;
with VSS.Implementation.UCD_Casing_UTF8;
with VSS.Implementation.UCD_Normalization_UTF8;

package body VSS.Implementation.UTF8_String_Handlers is

   use type VSS.Implementation.Strings.Character_Count;
   use type VSS.Unicode.UTF8_Code_Unit_Offset;
   use type VSS.Unicode.UTF16_Code_Unit_Offset;

   type Verification_State is
     (Initial,    --  ASCII or start of multibyte sequence
      U31,        --  A0 .. BF | UT1
      U33,        --  80 .. 9F | UT1
      U41,        --  90 .. BF | UT2
      U43,        --  80 .. 8F | UT2
      UT1,        --  1 (80 .. BF)
      UT2,        --  2 (80 .. BF)
      UT3,        --  3 (80 .. BF)
      Ill_Formed);
   --  Unicode defines well-formed UTF-8 as
   --
   --  00 .. 7F
   --  C2 .. DF | 80 .. BF
   --  E0       | A0 .. BF | 80 .. BF
   --  E1 .. EC | 80 .. BF | 80 .. BF
   --  ED       | 80 .. 9F | 80 .. BF
   --  EE .. EF | 80 .. BF | 80 .. BF
   --  F0       | 90 .. BF | 80 .. BF | 80 .. BF
   --  F1 .. F3 | 80 .. BF | 80 .. BF | 80 .. BF
   --  F4       | 80 .. 8F | 80 .. BF | 80 .. BF

   function Unchecked_Decode
     (Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Offset  : VSS.Unicode.UTF8_Code_Unit_Index)
      return VSS.Unicode.Code_Point;
   --  Decode UTF8 encoded character started at given offset

   procedure Unchecked_Decode_Forward
     (Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Offset  : in out VSS.Unicode.UTF8_Code_Unit_Index;
      Code    : out VSS.Unicode.Code_Point);
   --  Decode UTF8 encoded character started at given offset and change offset
   --  to point to the beginning of the next character.

   procedure Unchecked_Backward_Decode
     (Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Offset  : in out VSS.Unicode.UTF8_Code_Unit_Index;
      Code    : out VSS.Unicode.Code_Point);
   --  Change offset to the point of the previous character and decode
   --  character at this position.

   procedure Unchecked_Backward_Decode
     (Source_Data : VSS.Implementation.Strings.String_Data;
      Offset      : in out VSS.Unicode.UTF8_Code_Unit_Index;
      Code        : out VSS.Unicode.Code_Point);
   --  Change offset to the point of the previous character and decode
   --  character at this position.

   procedure Unchecked_Forward
     (Storage  : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Position : in out VSS.Implementation.Strings.Cursor);
   --  Move cursor to position of the next character

   --  procedure Unchecked_Forward
   --    (Source_Data : VSS.Implementation.Strings.String_Data;
   --     Offset      : in out VSS.Unicode.UTF8_Code_Unit_Count);
   --  --  Move cursor to position of the next character

   procedure Unchecked_Backward
     (Storage  : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Position : in out VSS.Implementation.Strings.Cursor);
   --  Move cursor to position of the previous character

   procedure Validate_And_Copy
     (Source      : Ada.Strings.UTF_Encoding.UTF_8_String;
      Destination : out VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Length      : out VSS.Implementation.Strings.Character_Count;
      Success     : out Boolean);
   --  Validate UTF-8 encoding and copy validated part of the data to
   --  Destination. Length is set to the length of the text in characters.
   --  Success is set False when validation is failed and to True otherwise.

   procedure Unchecked_Append
     (Target_Data : in out VSS.Implementation.Strings.String_Data;
      Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      From        : VSS.Unicode.UTF8_Code_Unit_Index;
      Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Length      : VSS.Implementation.Strings.Character_Count);
   --  Append given slice of the data to the target. Convert target
   --  from in-place to heap based implementation when necessary.

   procedure Unchecked_Append
     (Target_Data : in out VSS.Implementation.Strings.String_Data;
      Target_Size : out VSS.Unicode.UTF8_Code_Unit_Count;
      Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      From        : VSS.Unicode.UTF8_Code_Unit_Index;
      Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Length      : VSS.Implementation.Strings.Character_Count);
   --  Append given slice of the data to the target. Convert target
   --  from in-place to heap based implementation when necessary.

   procedure Unchecked_Insert
     (Target_Data : in out VSS.Implementation.Strings.String_Data;
      Target_Size : out VSS.Unicode.UTF8_Code_Unit_Count;
      Into        : VSS.Unicode.UTF8_Code_Unit_Index;
      Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      From        : VSS.Unicode.UTF8_Code_Unit_Index;
      Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Length      : VSS.Implementation.Strings.Character_Count);
   --  Insert given slice of the data into the target starting from the given
   --  position. Convert target from in-place to heap based implementation
   --  when necessary.

   Growth_Factor            : constant := 32;
   --  The growth factor controls how much extra space is allocated when
   --  we have to increase the size of an allocated unbounded string. By
   --  allocating extra space, we avoid the need to reallocate on every
   --  append, particularly important when a string is built up by repeated
   --  append operations of small pieces. This is expressed as a factor so
   --  32 means add 1/32 of the length of the string as growth space.

   Minimal_Allocation_Block : constant := Standard'Maximum_Alignment;
   --  Allocation will be done by a multiple of Minimal_Allocation_Block.
   --  This causes no memory loss as most (all?) malloc implementations are
   --  obliged to align the returned memory on the maximum alignment as malloc
   --  does not know the target alignment.

   function Aligned_Capacity
     (Capacity : VSS.Unicode.UTF8_Code_Unit_Count)
      return VSS.Unicode.UTF8_Code_Unit_Count;
   --  Returns recommended capacity of the string data storage which is greater
   --  or equal to the specified requested capacity. Calculation take in sense
   --  alignment of the allocated memory segments to use memory effectively by
   --  sequential operations which extends size of the buffer.

   function Allocate
     (Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count)
      return UTF8_String_Data_Access;
   --  Allocate storage block to store at least given amount of the data.

   procedure Reallocate
     (Data     : in out UTF8_String_Data_Access;
      Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count);
   --  Reallocates storage block to store at least given amount of the data.
   --  Content of the data will be copied, and old storage block will be
   --  unreferenced (and deallocated if it is no longer used).

   procedure Unreference (Data : in out UTF8_String_Data_Access);
   --  Decrement reference counter and deallocate storage block when reference
   --  counter reach zero.

   procedure Mutate
     (Data     : in out UTF8_String_Data_Access;
      Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count);
   --  Reallocate storage block when it is shared or not enough to store given
   --  amount of data.

   procedure Copy_To_Heap
     (Data     : in out VSS.Implementation.Strings.String_Data;
      Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count)
     with Pre => Data.In_Place,
          Post => not Data.In_Place;
   --  Turn "in place" string data into a heap allocated one.
   --  Use expected Capacity and Size to allocate a storage block, then copy
   --  string content to the allocated block.

   procedure Split_Lines_Common
     (Handler         :
        VSS.Implementation.String_Handlers.Abstract_String_Handler'Class;
      Data            : VSS.Implementation.Strings.String_Data;
      Storage         : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Terminators     : VSS.Strings.Line_Terminator_Set;
      Keep_Terminator : Boolean;
      Lines           : in out
        VSS.Implementation.String_Vectors.String_Vector_Data_Access);
   --  Common code of Split_Lines subprogram for on heap and inline handlers.

   function Get_Case_Mapping_Information
     (Mapping : VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset_Array;
      Code    : VSS.Unicode.Code_Point)
      return VSS.Implementation.UCD_Casing_UTF8.Mapping_Information;
   --  Returns case mapping information for given mapping and character.

   function Get_Decomposition_Information
     (Decomposition_Data :
        VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Offset_Array;
      Code               : VSS.Unicode.Code_Point)
      return VSS.Implementation.UCD_Normalization_UTF8.Mapping_Information;
   --  Returns decomposition information for given data and character.

   procedure Convert_Case_Simple
     (Source_Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Source_Size    : VSS.Unicode.UTF8_Code_Unit_Count;
      Mapping        :
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset_Array;
      Result_Data    : in out VSS.Implementation.Strings.String_Data);
   --  Common code for simple case conversions.

   procedure Convert_Case_Full
     (Source_Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Source_Size    : VSS.Unicode.UTF8_Code_Unit_Count;
      Mapping        :
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset_Array;
      To_Lower       : Boolean;
      Result_Data    : in out VSS.Implementation.Strings.String_Data);
   --  Common code for full case conversions.

   procedure Decomposite
     (Source_Storage     :
        VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Source_Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Decomposition_Data :
        VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Offset_Array;
      Result_Data        : out VSS.Implementation.Strings.String_Data);
   --  Common code to decomposite string according to given decomposition
   --  mapping (canonical or compatibility) and to do canonical reordering.

   --------------------------
   -- After_Last_Character --
   --------------------------

   overriding procedure After_Last_Character
     (Self     : UTF8_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor)
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      Position :=
        (Index        => Source.Length + 1,
         UTF8_Offset  => Source.Size,
         UTF16_Offset => 0);
   end After_Last_Character;

   --------------------------
   -- After_Last_Character --
   --------------------------

   overriding procedure After_Last_Character
     (Self     : UTF8_In_Place_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor)
   is
      Source : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      Position :=
        (Index        =>
           VSS.Implementation.Strings.Character_Count (Source.Length) + 1,
         UTF8_Offset  => Source.Size,
         UTF16_Offset => 0);
   end After_Last_Character;

   ----------------------
   -- Aligned_Capacity --
   ----------------------

   function Aligned_Capacity
     (Capacity : VSS.Unicode.UTF8_Code_Unit_Count)
      return VSS.Unicode.UTF8_Code_Unit_Count
   is
      subtype Empty_UTF8_String_Data is UTF8_String_Data (0);

      Static_Size : constant VSS.Unicode.UTF8_Code_Unit_Count :=
        Empty_UTF8_String_Data'Max_Size_In_Storage_Elements;

   begin
      return
        ((Static_Size + Capacity) / Minimal_Allocation_Block + 1)
          * Minimal_Allocation_Block - Static_Size;
   end Aligned_Capacity;

   --------------
   -- Allocate --
   --------------

   function Allocate
     (Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count)
      return UTF8_String_Data_Access is
   begin
      return
        new UTF8_String_Data
              (Aligned_Capacity
                 (VSS.Unicode.UTF8_Code_Unit_Count'Max (Capacity, Size)));
   end Allocate;

   ------------
   -- Append --
   ------------

   overriding procedure Append
     (Self   : UTF8_String_Handler;
      Data   : in out VSS.Implementation.Strings.String_Data;
      Code   : VSS.Unicode.Code_Point;
      Offset : in out VSS.Implementation.Strings.Cursor_Offset)
   is
      Destination : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;
      L           : VSS.Implementation.UTF8_Encoding.UTF8_Sequence_Length;
      U1          : VSS.Unicode.UTF8_Code_Unit;
      U2          : VSS.Unicode.UTF8_Code_Unit;
      U3          : VSS.Unicode.UTF8_Code_Unit;
      U4          : VSS.Unicode.UTF8_Code_Unit;

   begin
      VSS.Implementation.UTF8_Encoding.Encode (Code, L, U1, U2, U3, U4);

      Offset.Index_Offset := Offset.Index_Offset + 1;
      Offset.UTF8_Offset  := Offset.UTF8_Offset + L;
      Offset.UTF16_Offset := Offset.UTF16_Offset + (if L = 4 then 2 else 1);

      Mutate
        (Destination,
         VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity) * 4,
         (if Destination = null then 0 else Destination.Size) + L);

      VSS.Implementation.UTF8_Encoding.Unchecked_Store
        (Destination.Storage, Destination.Size, L, U1, U2, U3, U4);

      Destination.Size := Destination.Size + L;
      Destination.Length := Destination.Length + 1;
      Destination.Storage (Destination.Size) := 16#00#;
   end Append;

   ------------
   -- Append --
   ------------

   overriding procedure Append
     (Self   : UTF8_String_Handler;
      Data   : in out VSS.Implementation.Strings.String_Data;
      Suffix : VSS.Implementation.Strings.String_Data;
      Offset : in out VSS.Implementation.Strings.Cursor_Offset)
   is
      Parent : VSS.Implementation.String_Handlers.Abstract_String_Handler
        renames VSS.Implementation.String_Handlers.Abstract_String_Handler
                 (Self);
      Source         : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;
      Suffix_Handler :
        constant not null VSS.Implementation.Strings.String_Handler_Access :=
          VSS.Implementation.Strings.Handler (Suffix);

   begin
      if Suffix_Handler.all in UTF8_In_Place_String_Handler then
         --  When suffix is "in place", we can use its size to calculate
         --  result size in advance.
         declare
            Suffix_Data : UTF8_In_Place_Data
              with Import, Convention => Ada, Address => Suffix'Address;

         begin
            Mutate
              (Source,
               VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity) * 4,
               Source.Size + Suffix_Data.Size);

            --  Copy character by character
            Parent.Append (Data, Suffix, Offset);
         end;

      elsif Suffix_Handler.all not in UTF8_String_Handler then
         --  No other optimization is possible here, copy character by
         --  character
         Parent.Append (Data, Suffix, Offset);

      else  --  Both Data and suffix are not "in place"

         declare
            use type VSS.Unicode.UTF8_Code_Unit;

            Suffix_Data : UTF8_String_Data_Access
              with Import,
                Convention => Ada,
                Address    => Suffix.Pointer'Address;
            New_Size    : constant VSS.Unicode.UTF8_Code_Unit_Count :=
              Source.Size + Suffix_Data.Size;
            UTF16_Size  : VSS.Unicode.UTF16_Code_Unit_Offset :=
              VSS.Unicode.UTF16_Code_Unit_Offset (Suffix_Data.Length);

         begin
            Mutate
              (Source,
               VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity) * 4,
               New_Size);

            for J in 0 .. Suffix_Data.Size loop
               Source.Storage (Source.Size + J) := Suffix_Data.Storage (J);

               if (Suffix_Data.Storage (J) and 2#1111_1000#)
                 = 2#1111_0000#
               then
                  UTF16_Size := UTF16_Size + 1;
               end if;
            end loop;

            Source.Size := New_Size;
            Source.Length := Source.Length + Suffix_Data.Length;

            Offset.Index_Offset := Offset.Index_Offset + Suffix_Data.Length;
            Offset.UTF8_Offset  := Offset.UTF8_Offset + Suffix_Data.Size;
            Offset.UTF16_Offset := Offset.UTF16_Offset + UTF16_Size;
         end;
      end if;
   end Append;

   ------------
   -- Append --
   ------------

   overriding procedure Append
     (Self   : UTF8_In_Place_String_Handler;
      Data   : in out VSS.Implementation.Strings.String_Data;
      Code   : VSS.Unicode.Code_Point;
      Offset : in out VSS.Implementation.Strings.Cursor_Offset)
   is
      Destination : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;
      L           : VSS.Implementation.UTF8_Encoding.UTF8_Sequence_Length;
      U1          : VSS.Unicode.UTF8_Code_Unit;
      U2          : VSS.Unicode.UTF8_Code_Unit;
      U3          : VSS.Unicode.UTF8_Code_Unit;
      U4          : VSS.Unicode.UTF8_Code_Unit;

   begin
      VSS.Implementation.UTF8_Encoding.Encode (Code, L, U1, U2, U3, U4);

      Offset.Index_Offset := Offset.Index_Offset + 1;
      Offset.UTF8_Offset  := Offset.UTF8_Offset + L;
      Offset.UTF16_Offset := Offset.UTF16_Offset + (if L = 4 then 2 else 1);

      if Destination.Size + L < Destination.Storage'Length then
         --  There is enough space to store data in place.

         VSS.Implementation.UTF8_Encoding.Unchecked_Store
           (Destination.Storage, Destination.Size, L, U1, U2, U3, U4);

         Destination.Size := Destination.Size + L;
         Destination.Length := Destination.Length + 1;
         Destination.Storage (Destination.Size) := 16#00#;

      else
         --  Data can't be stored "in place" and need to be converted into
         --  shared data.
         declare
            Source      : UTF8_In_Place_Data
              with Import, Convention => Ada, Address => Data'Address;
         begin
            Copy_To_Heap
              (Data,
               VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity * 4),
               Source.Size + L);
         end;

         declare
            Destination : UTF8_String_Data_Access
              with Import, Convention => Ada, Address => Data.Pointer'Address;

         begin
            VSS.Implementation.UTF8_Encoding.Unchecked_Store
              (Destination.Storage, Destination.Size, L, U1, U2, U3, U4);

            Destination.Size := Destination.Size + L;
            Destination.Length := Destination.Length + 1;
            Destination.Storage (Destination.Size) := 16#00#;
         end;
      end if;
   end Append;

   ------------
   -- Append --
   ------------

   overriding procedure Append
     (Self   : UTF8_In_Place_String_Handler;
      Data   : in out VSS.Implementation.Strings.String_Data;
      Suffix : VSS.Implementation.Strings.String_Data;
      Offset : in out VSS.Implementation.Strings.Cursor_Offset)
   is
      Parent : VSS.Implementation.String_Handlers.Abstract_String_Handler
        renames VSS.Implementation.String_Handlers.Abstract_String_Handler
                 (Self);

      Source         : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;
      Suffix_Handler :
        constant not null VSS.Implementation.Strings.String_Handler_Access :=
          VSS.Implementation.Strings.Handler (Suffix);

   begin
      if Suffix_Handler.all in UTF8_String_Handler then
         --  The Suffix isn't storred "in place", so the result can't be stored
         --  "in place" neither. Let's convert it into a shared data and then
         --  process as "in heap" string.

         declare
            Suffix_Data : UTF8_String_Data_Access
              with Import,
                Convention => Ada,
                Address    => Suffix.Pointer'Address;

         begin
            Copy_To_Heap
              (Data,
               VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity * 4),
               Source.Size + Suffix_Data.Size);

            Suffix_Handler.Append (Data, Suffix, Offset);
         end;

      elsif Suffix_Handler.all not in UTF8_In_Place_String_Handler then
         --  Can't optimize, use char-by-char append
         Parent.Append (Data, Suffix, Offset);

      else  --  Both Data and suffix are "in place"
         declare
            use type VSS.Unicode.UTF8_Code_Unit;

            Suffix_Data : UTF8_In_Place_Data
              with Import, Convention => Ada, Address => Suffix'Address;

            Old_Size   : constant VSS.Unicode.UTF8_Code_Unit_Count :=
              Source.Size;
            New_Size   : constant VSS.Unicode.UTF8_Code_Unit_Count :=
              Old_Size + Suffix_Data.Size;
            UTF16_Size : VSS.Unicode.UTF16_Code_Unit_Offset :=
              VSS.Unicode.UTF16_Code_Unit_Offset (Suffix_Data.Length);

         begin
            if New_Size < Source.Storage'Length then
               --  There is enough space to store data in place.

               Source.Length := Source.Length + Suffix_Data.Length;

               for J in 0 .. Suffix_Data.Size loop
                  Source.Storage (Old_Size + J) := Suffix_Data.Storage (J);

                  if (Suffix_Data.Storage (J) and 2#1111_1000#)
                    = 2#1111_0000#
                  then
                     UTF16_Size := UTF16_Size + 1;
                  end if;
               end loop;

               Source.Size := New_Size;

               Offset.Index_Offset :=
                 Offset.Index_Offset
                   + VSS.Implementation.Strings.Character_Count
                       (Suffix_Data.Length);
               Offset.UTF8_Offset  := Offset.UTF8_Offset + Suffix_Data.Size;
               Offset.UTF16_Offset := Offset.UTF16_Offset + UTF16_Size;

            else
               --  Data can't be stored "in place" and need to be converted
               --  into a shared data.

               Copy_To_Heap
                 (Data,
                  VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity * 4),
                  New_Size);

               --  Copy character by character
               VSS.Implementation.String_Handlers.Abstract_String_Handler
                 (Global_UTF8_String_Handler).Append (Data, Suffix, Offset);
            end if;
         end;
      end if;
   end Append;

   --------------
   -- Backward --
   --------------

   overriding function Backward
     (Self     : UTF8_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor) return Boolean
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      if Source = null or else Position.Index = 0 then
         return False;

      else
         Unchecked_Backward (Source.Storage, Position);
      end if;

      return Position.Index > 0;
   end Backward;

   --------------
   -- Backward --
   --------------

   overriding function Backward
     (Self     : UTF8_In_Place_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor) return Boolean
   is
      Source : constant UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      if Position.Index = 0 then
         return False;

      else
         Unchecked_Backward (Source.Storage, Position);
      end if;

      return Position.Index > 0;
   end Backward;

   ----------------------------
   -- Before_First_Character --
   ----------------------------

   overriding procedure Before_First_Character
     (Self     : UTF8_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor) is
   begin
      Position := (Index => 0, UTF8_Offset => -1, UTF16_Offset => -1);
   end Before_First_Character;

   ----------------------------
   -- Before_First_Character --
   ----------------------------

   overriding procedure Before_First_Character
     (Self     : UTF8_In_Place_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor) is
   begin
      Position := (Index => 0, UTF8_Offset => -1, UTF16_Offset => -1);
   end Before_First_Character;

   ------------------
   -- Convert_Case --
   ------------------

   overriding procedure Convert_Case
     (Self    : UTF8_String_Handler;
      Data    : VSS.Implementation.Strings.String_Data;
      Mapping : VSS.Implementation.String_Handlers.Case_Mapping;
      Result  : out VSS.Implementation.Strings.String_Data)
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      Self.Initialize (Result);

      if Self.Is_Empty (Data) then
         --  Nothing to do for an empty string.

         return;
      end if;

      declare
         Target : UTF8_String_Data_Access
           with Import, Convention => Ada, Address => Result.Pointer'Address;

      begin
         Target :=
           Allocate
             (VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity) * 4,
              Source.Size);
      end;

      case Mapping is
         when VSS.Implementation.String_Handlers.Simple_Lowercase =>
            Convert_Case_Simple
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Simple_Lowercase_Index,
               Result);

         when VSS.Implementation.String_Handlers.Simple_Titlecase =>
            raise Program_Error;

            --  Convert_Case_Simple
            --    (Source.Storage,
            --     Source.Size,
            --     VSS.Implementation.UCD_Casing_UTF8.Simple_Titlecase_Index,
            --     Result);

         when VSS.Implementation.String_Handlers.Simple_Uppercase =>
            Convert_Case_Simple
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Simple_Uppercase_Index,
               Result);

         when VSS.Implementation.String_Handlers.Lowercase =>
            Convert_Case_Full
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Full_Lowercase_Index,
               True,
               Result);

         when VSS.Implementation.String_Handlers.Titlecase =>
            raise Program_Error;

            --  Convert_Case_Full
            --    (Source.Storage,
            --     Source.Size,
            --     VSS.Implementation.UCD_Casing_UTF8.Full_Titlecase_Index,
            --     False,
            --     Result);

         when VSS.Implementation.String_Handlers.Uppercase =>
            Convert_Case_Full
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Full_Uppercase_Index,
               False,
               Result);
      end case;
   end Convert_Case;

   ------------------
   -- Convert_Case --
   ------------------

   overriding procedure Convert_Case
     (Self    : UTF8_In_Place_String_Handler;
      Data    : VSS.Implementation.Strings.String_Data;
      Mapping : VSS.Implementation.String_Handlers.Case_Mapping;
      Result  : out VSS.Implementation.Strings.String_Data)
   is
      Source : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      Self.Initialize (Result);

      case Mapping is
         when VSS.Implementation.String_Handlers.Simple_Lowercase =>
            Convert_Case_Simple
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Simple_Lowercase_Index,
               Result);

         when VSS.Implementation.String_Handlers.Simple_Titlecase =>
            raise Program_Error;

            --  Convert_Case_Simple
            --    (Source.Storage,
            --     Source.Size,
            --     VSS.Implementation.UCD_Casing_UTF8.Simple_Titlecase_Index,
            --     Result);

         when VSS.Implementation.String_Handlers.Simple_Uppercase =>
            Convert_Case_Simple
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Simple_Uppercase_Index,
               Result);

         when VSS.Implementation.String_Handlers.Lowercase =>
            Convert_Case_Full
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Full_Lowercase_Index,
               True,
               Result);

         when VSS.Implementation.String_Handlers.Titlecase =>
            raise Program_Error;

            --  Convert_Case_Full
            --    (Source.Storage,
            --     Source.Size,
            --     VSS.Implementation.UCD_Casing_UTF8.Full_Titlecase_Index,
            --     False,
            --     Result);

         when VSS.Implementation.String_Handlers.Uppercase =>
            Convert_Case_Full
              (Source.Storage,
               Source.Size,
               VSS.Implementation.UCD_Casing_UTF8.Full_Uppercase_Index,
               False,
               Result);
      end case;
   end Convert_Case;

   -----------------------
   -- Convert_Case_Full --
   -----------------------

   procedure Convert_Case_Full
     (Source_Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Source_Size    : VSS.Unicode.UTF8_Code_Unit_Count;
      Mapping        :
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset_Array;
      To_Lower       : Boolean;
      Result_Data    : in out VSS.Implementation.Strings.String_Data)
   is
      Code    : VSS.Unicode.Code_Point;
      Start   : VSS.Unicode.UTF8_Code_Unit_Offset;
      Offset  : VSS.Unicode.UTF8_Code_Unit_Offset := 0;
      Context : VSS.Implementation.UCD_Casing.Casing_Context;

   begin
      while Offset < Source_Size loop
         Start := Offset;
         Unchecked_Decode_Forward (Source_Storage, Offset, Code);

         declare
            use type VSS.Unicode.Code_Point;

            Info : constant
              VSS.Implementation.UCD_Casing_UTF8.Mapping_Information :=
                Get_Case_Mapping_Information (Mapping, Code);
            Skip : Boolean := False;

         begin
            if To_Lower and Context.Final_Sigma and Code = 16#03A3# then
               declare
                  Suffix_Offset : VSS.Unicode.UTF8_Code_Unit_Offset := Offset;
                  Match         : Boolean := False;
                  Suffix_Info   :
                    VSS.Implementation.UCD_Casing_UTF8.Mapping_Information;

               begin
                  while Suffix_Offset < Source_Size loop
                     Unchecked_Decode_Forward
                       (Source_Storage, Suffix_Offset, Code);
                     Suffix_Info :=
                       Get_Case_Mapping_Information (Mapping, Code);

                     if Suffix_Info.Case_Ignorable then
                        null;

                     else
                        Match := Suffix_Info.Cased;

                        exit;
                     end if;
                  end loop;

                  if not Match then
                     --  Replace by 03C2

                     Unchecked_Append (Result_Data, (16#CF#, 16#82#), 0, 2, 1);
                     Skip := True;
                  end if;
               end;
            end if;

            VSS.Implementation.UCD_Casing.Apply (Context, Info.Context_Change);

            if not Skip then
               if Info.Has_Mapping then
                  Unchecked_Append
                    (Result_Data,
                     VSS.Implementation.UCD_Casing_UTF8.UTF8_Data_Table,
                     Info.Offset,
                     Info.Count,
                     Info.Length);

               else
                  Unchecked_Append
                    (Result_Data, Source_Storage, Start, Offset - Start, 1);
               end if;
            end if;
         end;
      end loop;
   end Convert_Case_Full;

   -------------------------
   -- Convert_Case_Simple --
   -------------------------

   procedure Convert_Case_Simple
     (Source_Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Source_Size    : VSS.Unicode.UTF8_Code_Unit_Count;
      Mapping        :
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset_Array;
      Result_Data    : in out VSS.Implementation.Strings.String_Data)
   is
      Code   : VSS.Unicode.Code_Point;
      Start  : VSS.Unicode.UTF8_Code_Unit_Offset;
      Offset : VSS.Unicode.UTF8_Code_Unit_Offset := 0;

   begin
      while Offset < Source_Size loop
         Start := Offset;
         Unchecked_Decode_Forward (Source_Storage, Offset, Code);

         declare
            Info : constant
              VSS.Implementation.UCD_Casing_UTF8.Mapping_Information :=
                Get_Case_Mapping_Information (Mapping, Code);

         begin
            if Info.Has_Mapping then
               Unchecked_Append
                 (Result_Data,
                  VSS.Implementation.UCD_Casing_UTF8.UTF8_Data_Table,
                  Info.Offset,
                  Info.Count,
                  Info.Length);

            else
               Unchecked_Append
                 (Result_Data, Source_Storage, Start, Offset - Start, 1);
            end if;
         end;
      end loop;
   end Convert_Case_Simple;

   ------------------
   -- Copy_To_Heap --
   ------------------

   procedure Copy_To_Heap
     (Data     : in out VSS.Implementation.Strings.String_Data;
      Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count)
   is
      Source : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

      Destination : constant UTF8_String_Data_Access :=
        Allocate (Capacity, Size);

   begin
      Destination.Storage (0 .. Source.Size) :=
        Source.Storage (0 .. Source.Size);
      Destination.Length := Source.Length;
      Destination.Size   := Source.Size;

      Data :=
        (In_Place => False,
         Capacity => Data.Capacity,
         Padding  => False,
         Handler  => Global_UTF8_String_Handler'Access,
         Pointer  => Destination.all'Address);
   end Copy_To_Heap;

   -----------------
   -- Decomposite --
   -----------------

   procedure Decomposite
     (Source_Storage     :
        VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Source_Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Decomposition_Data :
        VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Offset_Array;
      Result_Data        : out VSS.Implementation.Strings.String_Data)
   is
      use all type VSS.Implementation.UCD_Normalization_UTF8.CCC_Values;
      use type VSS.Unicode.Code_Point;

      procedure Reorder_And_Insert
        (Result_Data : in out VSS.Implementation.Strings.String_Data;
         Result_Size : in out VSS.Unicode.UTF8_Code_Unit_Count;
         CCC         : VSS.Implementation.UCD_Normalization_UTF8.CCC_Values;
         Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
         Offset      : VSS.Unicode.UTF8_Code_Unit_Offset;
         Size        : VSS.Unicode.UTF8_Code_Unit_Count);
      --  Insert given encoded character into the string preserving canonical
      --  ordering.

      ------------------------
      -- Reorder_And_Insert --
      ------------------------

      procedure Reorder_And_Insert
        (Result_Data : in out VSS.Implementation.Strings.String_Data;
         Result_Size : in out VSS.Unicode.UTF8_Code_Unit_Count;
         CCC         : VSS.Implementation.UCD_Normalization_UTF8.CCC_Values;
         Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
         Offset      : VSS.Unicode.UTF8_Code_Unit_Offset;
         Size        : VSS.Unicode.UTF8_Code_Unit_Count)
      is
         Previous_Offset : VSS.Unicode.UTF8_Code_Unit_Offset;
         Previous_Code   : VSS.Unicode.Code_Point;
         Previous_Info   :
           VSS.Implementation.UCD_Normalization_UTF8.Mapping_Information;
         Insert_Offset   : VSS.Unicode.UTF8_Code_Unit_Offset;

      begin
         Previous_Offset := Result_Size;

         loop
            Insert_Offset := Previous_Offset;

            exit when Previous_Offset = 0;

            Unchecked_Backward_Decode
              (Result_Data, Previous_Offset, Previous_Code);

            Previous_Info :=
              Get_Decomposition_Information
                (Decomposition_Data, Previous_Code);

            exit when Previous_Info.CCC = CCC_NR
                        or Previous_Info.CCC <= CCC;
         end loop;

         Unchecked_Insert
           (Result_Data,
            Result_Size,
            Insert_Offset,
            Storage,
            Offset,
            Size,
            1);
      end Reorder_And_Insert;

      Result_Size : VSS.Unicode.UTF8_Code_Unit_Count := 0;
      Code        : VSS.Unicode.Code_Point;
      Info        :
        VSS.Implementation.UCD_Normalization_UTF8.Mapping_Information;
      Start       : VSS.Unicode.UTF8_Code_Unit_Offset;
      Out_Start   : VSS.Unicode.UTF8_Code_Unit_Offset;
      Offset      : VSS.Unicode.UTF8_Code_Unit_Offset := 0;
      Length      : VSS.Implementation.Strings.Character_Count;
      Last_CCC    : VSS.Implementation.UCD_Normalization_UTF8.CCC_Values :=
        VSS.Implementation.UCD_Normalization_UTF8.CCC_NR;

   begin
      loop
         --  Check whether source string is in normalization form, and attempt
         --  to lookup for maximum length of normalized data.

         Start  := Offset;
         Length := 0;

         loop
            Out_Start := Offset;

            exit when Offset >= Source_Size;

            Unchecked_Decode_Forward (Source_Storage, Offset, Code);

            Info := Get_Decomposition_Information (Decomposition_Data, Code);

            exit when not Info.Decomposition_QC;
            --  Copy data and run normalization

            exit when Last_CCC > Info.CCC and Info.CCC /= CCC_NR;
            --  Copy data and run reordering

            Last_CCC := Info.CCC;
            Length   := Length + 1;
         end loop;

         --  Copy found normalized data if any

         if Start /= Out_Start then
            Unchecked_Append
              (Result_Data,
               Result_Size,
               Source_Storage,
               Start,
               Out_Start - Start,
               Length);
         end if;

         exit when Out_Start >= Source_Size;
         --  Source text has been processed completely, exit.

         if Info.Decomposition_QC then
            --  Apply canonical ordering algoriphm to the next character in
            --  the source string.

            Reorder_And_Insert
              (Result_Data,
               Result_Size,
               Info.CCC,
               Source_Storage,
               Out_Start,
               Offset - Out_Start);

         else
            --  Apply decomposition mapping

            if Code in 16#AC00# .. 16#AC00# + 11_172 then
               --  Hangul syllables are decomposed algorithmically.

               declare
                  use type VSS.Unicode.UTF8_Code_Unit;

                  S_Base  : constant := 16#AC00#;
                  L_Base  : constant := 16#1100#;
                  V_Base  : constant := 16#1161#;
                  T_Base  : constant := 16#11A7#;

                  T_Count : constant := 28;
                  N_Count : constant := 588;  --  V_Count * T_Count

                  S_Index : constant VSS.Unicode.Code_Point := Code - S_Base;
                  L_Index : constant VSS.Unicode.Code_Point :=
                    S_Index / N_Count;
                  V_Index : constant VSS.Unicode.Code_Point :=
                    (S_Index mod N_Count) / T_Count;
                  T_Index : constant VSS.Unicode.Code_Point :=
                    S_Index mod T_Count;
                  L_Part  : constant VSS.Unicode.Code_Point :=
                    L_Base + L_Index;
                  V_Part  : constant VSS.Unicode.Code_Point :=
                    V_Base + V_Index;
                  T_Part  : constant VSS.Unicode.Code_Point :=
                    T_Base + T_Index;

                  Aux : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array
                    (0 .. 8);

               begin
                  --  First byte of encoded seqeunce for all characters of the
                  --  decomposition is always 16#E1#, thus don't compute it and
                  --  ignore corresponding bits in L_Part/V_Part/T_Part.

                  Aux (0) := 16#E1#;
                  Aux (1) :=
                    16#80#
                      or VSS.Unicode.UTF8_Code_Unit
                           ((L_Part / 16#40#) mod 16#40#);
                  Aux (2) :=
                    16#80# or VSS.Unicode.UTF8_Code_Unit (L_Part mod 16#40#);

                  Aux (3) := 16#E1#;
                  Aux (4) :=
                    16#80#
                      or VSS.Unicode.UTF8_Code_Unit
                           ((V_Part / 16#40#) mod 16#40#);
                  Aux (5) :=
                    16#80# or VSS.Unicode.UTF8_Code_Unit (V_Part mod 16#40#);

                  if T_Index = 0 then
                     Unchecked_Append
                       (Result_Data,
                        Result_Size,
                        Aux,
                        0,
                        6,
                        2);

                  else
                     Aux (6) := 16#E1#;
                     Aux (7) :=
                       16#80#
                         or VSS.Unicode.UTF8_Code_Unit
                              ((T_Part / 16#40#) mod 16#40#);
                     Aux (8) :=
                       16#80#
                         or VSS.Unicode.UTF8_Code_Unit (T_Part mod 16#40#);

                     Unchecked_Append
                       (Result_Data,
                        Result_Size,
                        Aux,
                        0,
                        9,
                        3);
                  end if;

                  Last_CCC := CCC_NR;
               end;

            elsif Info.First_CCC /= CCC_NR
              and Last_CCC /= CCC_NR
              and Last_CCC > Info.First_CCC
            then
               --  Reordering is necessary

               declare
                  Next_Offset : VSS.Unicode.UTF8_Code_Unit_Offset :=
                    Info.Offset;
                  New_Offset  : VSS.Unicode.UTF8_Code_Unit_Offset;
                  New_Code    : VSS.Unicode.Code_Point;
                  New_Info    : VSS.Implementation.UCD_Normalization_UTF8
                                  .Mapping_Information;

               begin
                  loop
                     New_Offset := Next_Offset;

                     exit when Next_Offset >= Info.Offset + Info.Size;

                     Unchecked_Decode_Forward
                       (VSS.Implementation.UCD_Normalization_UTF8
                          .UTF8_Data_Table,
                        Next_Offset,
                        New_Code);

                     New_Info :=
                       Get_Decomposition_Information
                         (Decomposition_Data, New_Code);

                     if Last_CCC > New_Info.CCC then
                        Reorder_And_Insert
                          (Result_Data,
                           Result_Size,
                           New_Info.CCC,
                           VSS.Implementation.UCD_Normalization_UTF8
                             .UTF8_Data_Table,
                           New_Offset,
                           Next_Offset - New_Offset);

                     else
                        raise Program_Error;
                     end if;
                  end loop;
               end;

            else
               Unchecked_Append
                 (Result_Data,
                  Result_Size,
                  VSS.Implementation.UCD_Normalization_UTF8.UTF8_Data_Table,
                  Info.Offset,
                  Info.Size,
                  Info.Length);
               Last_CCC := Info.Last_CCC;
            end if;
         end if;

         exit when Offset >= Source_Size;
      end loop;
   end Decomposite;

   ------------
   -- Delete --
   ------------

   overriding procedure Delete
     (Self : UTF8_String_Handler;
      Data : in out VSS.Implementation.Strings.String_Data;
      From : VSS.Implementation.Strings.Cursor;
      Size : VSS.Implementation.Strings.Cursor_Offset)
   is
      Source   : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;
      New_Size : constant VSS.Unicode.UTF8_Code_Unit_Offset :=
        Source.Size - Size.UTF8_Offset;

   begin
      if Size.Index_Offset = 0 then
         return;
      end if;

      Source.Storage (From.UTF8_Offset .. New_Size) :=
        Source.Storage (From.UTF8_Offset + Size.UTF8_Offset .. Source.Size);

      Source.Length := Source.Length - Size.Index_Offset;
      Source.Size   := New_Size;
   end Delete;

   ------------
   -- Delete --
   ------------

   overriding procedure Delete
     (Self : UTF8_In_Place_String_Handler;
      Data : in out VSS.Implementation.Strings.String_Data;
      From : VSS.Implementation.Strings.Cursor;
      Size : VSS.Implementation.Strings.Cursor_Offset)
   is
      Source   : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;
      New_Size : constant VSS.Unicode.UTF8_Code_Unit_Offset :=
        Source.Size - Size.UTF8_Offset;

   begin
      if Size.Index_Offset = 0 then
         return;
      end if;

      Source.Storage (From.UTF8_Offset .. New_Size) :=
        Source.Storage (From.UTF8_Offset + Size.UTF8_Offset .. Source.Size);

      Source.Length := Source.Length - Size.Index_Offset;
      Source.Size   := New_Size;
   end Delete;

   -------------
   -- Element --
   -------------

   overriding function Element
     (Self     : UTF8_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : VSS.Implementation.Strings.Cursor)
      return VSS.Unicode.Code_Point
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      if Source = null
        or else Position.Index < 1
        or else Position.Index > Source.Length
      then
         return 16#00_0000#;
      end if;

      return Unchecked_Decode (Source.Storage, Position.UTF8_Offset);
   end Element;

   -------------
   -- Element --
   -------------

   overriding function Element
     (Self     : UTF8_In_Place_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : VSS.Implementation.Strings.Cursor)
      return VSS.Unicode.Code_Point
   is
      Source : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      --  raise Program_Error;

      if Position.Index < 1
        or else Position.Index
                  > VSS.Implementation.Strings.Character_Count (Source.Length)
      then
         return 16#00_0000#;
      end if;

      return Unchecked_Decode (Source.Storage, Position.UTF8_Offset);
   end Element;

   -------------
   -- Forward --
   -------------

   overriding function Forward
     (Self     : UTF8_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor) return Boolean
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      if Source = null or else Position.Index > Source.Length then
         return False;

      else
         Unchecked_Forward (Source.Storage, Position);
      end if;

      return Position.Index <= Source.Length;
   end Forward;

   -------------
   -- Forward --
   -------------

   overriding function Forward
     (Self     : UTF8_In_Place_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : in out VSS.Implementation.Strings.Cursor) return Boolean
   is
      Source : constant UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      if Position.Index
           > VSS.Implementation.Strings.Character_Count (Source.Length)
      then
         return False;

      else
         Unchecked_Forward (Source.Storage, Position);
      end if;

      return
        Position.Index
          <= VSS.Implementation.Strings.Character_Count (Source.Length);
   end Forward;

   -----------------------
   -- From_UTF_8_String --
   -----------------------

   overriding procedure From_UTF_8_String
     (Self    : in out UTF8_String_Handler;
      Item    : Ada.Strings.UTF_Encoding.UTF_8_String;
      Data    : out VSS.Implementation.Strings.String_Data;
      Success : out Boolean) is
   begin
      Data :=
        (In_Place => False,
         Padding  => False,
         Capacity => 0,
         Handler  => Self'Unchecked_Access,
         Pointer  => System.Null_Address);
      --  Initialize data.

      if Item'Length = 0 then
         --  Success := True;
         --
         --  return;
         raise Program_Error;
      end if;

      declare
         Destination : UTF8_String_Data_Access
           with Import, Convention => Ada, Address => Data.Pointer'Address;
         Length      : VSS.Implementation.Strings.Character_Count := 0;

      begin
         Destination := Allocate (0, Item'Length);

         Validate_And_Copy (Item, Destination.Storage, Length, Success);

         if Success then
            Destination.Storage
              (VSS.Unicode.UTF8_Code_Unit_Count (Item'Length)) := 16#00#;
            --  XXX GNAT 20210710 crash without type conversion
            Destination.Length := Length;
            Destination.Size   := Item'Length;

         else
            Self.Unreference (Data);
         end if;
      end;
   end From_UTF_8_String;

   -----------------------
   -- From_UTF_8_String --
   -----------------------

   overriding procedure From_UTF_8_String
     (Self    : in out UTF8_In_Place_String_Handler;
      Item    : Ada.Strings.UTF_Encoding.UTF_8_String;
      Data    : out VSS.Implementation.Strings.String_Data;
      Success : out Boolean) is
   begin
      Data :=
        (In_Place => True,
         Padding  => False,
         Capacity => 0,
         Storage  => <>);
      --  Initialize data.

      declare
         Destination : UTF8_In_Place_Data
           with Import, Convention => Ada, Address => Data.Storage'Address;
         Length      : VSS.Implementation.Strings.Character_Count;

      begin
         if Item'Length >= Destination.Storage'Length then
            --  There is not enoght space to store data

            Success := False;

            return;
         end if;

         Validate_And_Copy (Item, Destination.Storage, Length, Success);

         if Success then
            Destination.Storage (Item'Length) := 16#00#;
            Destination.Length := Length;
            Destination.Size   := Item'Length;
         end if;
      end;
   end From_UTF_8_String;

   ---------------------------
   -- From_Wide_Wide_String --
   ---------------------------

   overriding procedure From_Wide_Wide_String
     (Self    : in out UTF8_String_Handler;
      Item    : Wide_Wide_String;
      Data    : out VSS.Implementation.Strings.String_Data;
      Success : out Boolean) is
   begin
      Data :=
        (In_Place => False,
         Padding  => False,
         Capacity => 0,
         Handler  => Self'Unchecked_Access,
         Pointer  => System.Null_Address);
      --  Initialize data.

      Success := True;

      if Item'Length = 0 then
         --  Success := True;
         --
         --  return;
         raise Program_Error;
      end if;

      declare
         Destination : UTF8_String_Data_Access
           with Import, Convention => Ada, Address => Data.Pointer'Address;
         Code        : VSS.Unicode.Code_Point;
         L           : VSS.Implementation.UTF8_Encoding.UTF8_Sequence_Length;
         U1          : VSS.Unicode.UTF8_Code_Unit;
         U2          : VSS.Unicode.UTF8_Code_Unit;
         U3          : VSS.Unicode.UTF8_Code_Unit;
         U4          : VSS.Unicode.UTF8_Code_Unit;

      begin
         Destination := Allocate (0, Item'Length);

         for C of Item loop
            if Wide_Wide_Character'Pos (C) not in VSS.Unicode.Code_Point
              or else Wide_Wide_Character'Pos (C) in 16#D800# .. 16#DFFF#
            then
               Success := False;

               exit;

            else
               Code := Wide_Wide_Character'Pos (C);
            end if;

            VSS.Implementation.UTF8_Encoding.Encode (Code, L, U1, U2, U3, U4);

            if Destination.Bulk < Destination.Size + L then
               --  There is no enough storage to store character, reallocate
               --  memory.

               Reallocate
                 (Destination,
                  VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity) * 4,
                  Destination.Size + L);
            end if;

            VSS.Implementation.UTF8_Encoding.Unchecked_Store
              (Destination.Storage, Destination.Size, L, U1, U2, U3, U4);

            Destination.Size := Destination.Size + L;
         end loop;

         if Success then
            Destination.Storage (Destination.Size) := 16#00#;
            Destination.Length := Item'Length;

         else
            Self.Unreference (Data);
         end if;
      end;
   end From_Wide_Wide_String;

   ---------------------------
   -- From_Wide_Wide_String --
   ---------------------------

   overriding procedure From_Wide_Wide_String
     (Self    : in out UTF8_In_Place_String_Handler;
      Item    : Wide_Wide_String;
      Data    : out VSS.Implementation.Strings.String_Data;
      Success : out Boolean) is
   begin
      Data :=
        (In_Place => True,
         Padding  => False,
         Capacity => 0,
         Storage  => <>);
      --  Initialize data.

      Success := True;

      declare
         Destination : UTF8_In_Place_Data
           with Import, Convention => Ada, Address => Data.Storage'Address;
         Code        : VSS.Unicode.Code_Point;
         L           : VSS.Implementation.UTF8_Encoding.UTF8_Sequence_Length;
         U1          : VSS.Unicode.UTF8_Code_Unit;
         U2          : VSS.Unicode.UTF8_Code_Unit;
         U3          : VSS.Unicode.UTF8_Code_Unit;
         U4          : VSS.Unicode.UTF8_Code_Unit;

      begin
         Destination.Size := 0;

         for C of Item loop
            if Wide_Wide_Character'Pos (C) not in VSS.Unicode.Code_Point
              or else Wide_Wide_Character'Pos (C) in 16#D800# .. 16#DFFF#
            then
               Success := False;

               exit;

            else
               Code := Wide_Wide_Character'Pos (C);
            end if;

            VSS.Implementation.UTF8_Encoding.Encode (Code, L, U1, U2, U3, U4);

            if Destination.Storage'Last < Destination.Size + L then
               Success := False;

               exit;
            end if;

            VSS.Implementation.UTF8_Encoding.Unchecked_Store
              (Destination.Storage, Destination.Size, L, U1, U2, U3, U4);

            Destination.Size := Destination.Size + L;
         end loop;

         if Success then
            Destination.Length := Item'Length;
            Destination.Storage (Destination.Size) := 16#00#;
         end if;
      end;
   end From_Wide_Wide_String;

   ----------------------
   -- Get_Case_Mapping --
   ----------------------

   overriding procedure Get_Case_Mapping
     (Self    : UTF8_String_Handler;
      Code    : VSS.Unicode.Code_Point;
      Mapping : VSS.Implementation.String_Handlers.Case_Mapping;
      Data    : out VSS.Implementation.Strings.String_Data)
   is
      Target : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      raise Program_Error;
   end Get_Case_Mapping;

   ----------------------
   -- Get_Case_Mapping --
   ----------------------

   overriding procedure Get_Case_Mapping
     (Self    : UTF8_In_Place_String_Handler;
      Code    : VSS.Unicode.Code_Point;
      Mapping : VSS.Implementation.String_Handlers.Case_Mapping;
      Data    : out VSS.Implementation.Strings.String_Data)
   is
      Info   : constant
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Information :=
          Get_Case_Mapping_Information
            ((case Mapping is
                when VSS.Implementation.String_Handlers.Simple_Lowercase =>
                  VSS.Implementation.UCD_Casing_UTF8.Simple_Lowercase_Index,
                when VSS.Implementation.String_Handlers.Simple_Titlecase =>
                  VSS.Implementation.UCD_Casing_UTF8.Simple_Titlecase_Index,
                when VSS.Implementation.String_Handlers.Simple_Uppercase =>
                  VSS.Implementation.UCD_Casing_UTF8.Simple_Uppercase_Index,
                when VSS.Implementation.String_Handlers.Lowercase =>
                  VSS.Implementation.UCD_Casing_UTF8.Full_Lowercase_Index,
                when VSS.Implementation.String_Handlers.Titlecase =>
                  VSS.Implementation.UCD_Casing_UTF8.Full_Titlecase_Index,
                when VSS.Implementation.String_Handlers.Uppercase =>
                  VSS.Implementation.UCD_Casing_UTF8.Full_Uppercase_Index),
             Code);

      Target : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      --  Amount of the data that might be stored in in-place object is know
      --  to be larger that largest case mapping, thus all checks for this case
      --  are omitted to don't have useless code.

      if Info.Has_Mapping then
         Target.Storage (0 .. Info.Count - 1) :=
           VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array
             (VSS.Implementation.UCD_Casing_UTF8.UTF8_Data_Table
                (Info.Offset .. Info.Offset + Info.Count - 1));
         Target.Length := Info.Length;
         Target.Size   := Info.Count;
         Target.Storage (Target.Size) := 16#00#;

      else
         declare
            L  : VSS.Implementation.UTF8_Encoding.UTF8_Sequence_Length;
            U1 : VSS.Unicode.UTF8_Code_Unit;
            U2 : VSS.Unicode.UTF8_Code_Unit;
            U3 : VSS.Unicode.UTF8_Code_Unit;
            U4 : VSS.Unicode.UTF8_Code_Unit;

         begin
            VSS.Implementation.UTF8_Encoding.Encode (Code, L, U1, U2, U3, U4);

            VSS.Implementation.UTF8_Encoding.Unchecked_Store
              (Target.Storage, 0, L, U1, U2, U3, U4);

            Target.Size   := L;
            Target.Length := 1;
            Target.Storage (Target.Size) := 16#00#;
         end;
      end if;
   end Get_Case_Mapping;

   ----------------------------------
   -- Get_Case_Mapping_Information --
   ----------------------------------

   function Get_Case_Mapping_Information
     (Mapping : VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset_Array;
      Code    : VSS.Unicode.Code_Point)
      return VSS.Implementation.UCD_Casing_UTF8.Mapping_Information
   is
      use type VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset;
      use type VSS.Unicode.Code_Point;

      Group  : constant VSS.Implementation.UCD_Casing_UTF8.Mapping_Group :=
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Group
          (Code / VSS.Implementation.UCD_Casing_UTF8.Mapping_Group_Size);
      Offset : constant
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset :=
          VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Offset
            (Code mod VSS.Implementation.UCD_Casing_UTF8.Mapping_Group_Size);

   begin
      return
        VSS.Implementation.UCD_Casing_UTF8.Mapping_Data_Table
          (Mapping (Group) + Offset);
   end Get_Case_Mapping_Information;

   -----------------------------------
   -- Get_Decomposition_Information --
   -----------------------------------

   function Get_Decomposition_Information
     (Decomposition_Data :
        VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Offset_Array;
      Code               : VSS.Unicode.Code_Point)
      return VSS.Implementation.UCD_Normalization_UTF8.Mapping_Information
   is
      use type VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Offset;
      use type VSS.Unicode.Code_Point;

      Group  :
        constant VSS.Implementation.UCD_Normalization_UTF8.Mapping_Group :=
          VSS.Implementation.UCD_Normalization_UTF8.Mapping_Group
            (Code
               / VSS.Implementation.UCD_Normalization_UTF8.Mapping_Group_Size);
      Offset : constant
        VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Offset :=
          VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Offset
            (Code
             mod VSS.Implementation.UCD_Normalization_UTF8.Mapping_Group_Size);

   begin
      return
        VSS.Implementation.UCD_Normalization_UTF8.Mapping_Data_Table
          (Decomposition_Data (Group) + Offset);
   end Get_Decomposition_Information;

   -------------------
   -- Has_Character --
   -------------------

   overriding function Has_Character
     (Self     : UTF8_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : VSS.Implementation.Strings.Cursor) return Boolean
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      return
        Source /= null
          and then Position.Index > 0
          and then Position.Index <= Source.Length;
   end Has_Character;

   -------------------
   -- Has_Character --
   -------------------

   overriding function Has_Character
     (Self     : UTF8_In_Place_String_Handler;
      Data     : VSS.Implementation.Strings.String_Data;
      Position : VSS.Implementation.Strings.Cursor) return Boolean
   is
      Source : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      return
        Position.Index > 0
          and then Position.Index
            <= VSS.Implementation.Strings.Character_Count (Source.Length);
   end Has_Character;

   ----------------
   -- Initialize --
   ----------------

   overriding procedure Initialize
     (Self : UTF8_String_Handler;
      Data : out VSS.Implementation.Strings.String_Data) is
   begin
      Data :=
        (In_Place => False,
         Capacity => 0,
         Handler  => Self'Unrestricted_Access,
         Pointer  => System.Null_Address,
         Padding  => False);
   end Initialize;

   ----------------
   -- Initialize --
   ----------------

   overriding procedure Initialize
     (Self : UTF8_In_Place_String_Handler;
      Data : out VSS.Implementation.Strings.String_Data) is
   begin
      Data :=
        (In_Place => True,
         Capacity => 0,
         Storage  => <>,
         --  Handler  => Self'Unrestricted_Access,
         --  Pointer  => SYstem.Null_Address,
         Padding  => False);

      declare
         Target : UTF8_In_Place_Data
           with Import, Convention => Ada, Address => Data'Address;

      begin
         Target := (Storage => <>, Size => 0, Length => 0);
      end;
   end Initialize;

   ------------
   -- Insert --
   ------------

   overriding procedure Insert
     (Self   : UTF8_String_Handler;
      Data   : in out VSS.Implementation.Strings.String_Data;
      From   : VSS.Implementation.Strings.Cursor;
      Item   : VSS.Unicode.Code_Point;
      Offset : in out VSS.Implementation.Strings.Cursor_Offset)
   is
      Destination : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;
      L           : VSS.Implementation.UTF8_Encoding.UTF8_Sequence_Length;
      U1          : VSS.Unicode.UTF8_Code_Unit;
      U2          : VSS.Unicode.UTF8_Code_Unit;
      U3          : VSS.Unicode.UTF8_Code_Unit;
      U4          : VSS.Unicode.UTF8_Code_Unit;

   begin
      if VSS.Implementation.Strings.Is_Invalid (From) then
         return;
      end if;

      VSS.Implementation.UTF8_Encoding.Encode (Item, L, U1, U2, U3, U4);

      Offset.Index_Offset := Offset.Index_Offset + 1;
      Offset.UTF8_Offset  := Offset.UTF8_Offset + L;
      Offset.UTF16_Offset := Offset.UTF16_Offset + (if L = 4 then 2 else 1);

      Mutate
        (Destination,
         VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity) * 4,
         (if Destination = null then 0 else Destination.Size) + L);

      Destination.Storage
        (From.UTF8_Offset + L .. Destination.Size + L) :=
           Destination.Storage (From.UTF8_Offset .. Destination.Size);

      VSS.Implementation.UTF8_Encoding.Unchecked_Store
        (Destination.Storage, From.UTF8_Offset, L, U1, U2, U3, U4);

      Destination.Size := Destination.Size + L;
      Destination.Length := Destination.Length + 1;
      Destination.Storage (Destination.Size) := 16#00#;
   end Insert;

   ------------
   -- Insert --
   ------------

   overriding procedure Insert
     (Self   : UTF8_In_Place_String_Handler;
      Data   : in out VSS.Implementation.Strings.String_Data;
      From   : VSS.Implementation.Strings.Cursor;
      Item   : VSS.Unicode.Code_Point;
      Offset : in out VSS.Implementation.Strings.Cursor_Offset)
   is
      Destination  : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

      L           : VSS.Implementation.UTF8_Encoding.UTF8_Sequence_Length;
      U1          : VSS.Unicode.UTF8_Code_Unit;
      U2          : VSS.Unicode.UTF8_Code_Unit;
      U3          : VSS.Unicode.UTF8_Code_Unit;
      U4          : VSS.Unicode.UTF8_Code_Unit;

   begin
      if VSS.Implementation.Strings.Is_Invalid (From) then
         return;
      end if;

      VSS.Implementation.UTF8_Encoding.Encode (Item, L, U1, U2, U3, U4);

      Offset.Index_Offset := Offset.Index_Offset + 1;
      Offset.UTF8_Offset  := Offset.UTF8_Offset + L;
      Offset.UTF16_Offset := Offset.UTF16_Offset + (if L = 4 then 2 else 1);

      if Destination.Size + L < Destination.Storage'Length then
         --  There is enough space to store data in place.

         Destination.Storage
           (From.UTF8_Offset + L .. Destination.Size + L) :=
              Destination.Storage (From.UTF8_Offset .. Destination.Size);

         VSS.Implementation.UTF8_Encoding.Unchecked_Store
           (Destination.Storage, From.UTF8_Offset, L, U1, U2, U3, U4);

         Destination.Size   := Destination.Size + L;
         Destination.Length := Destination.Length + 1;
         Destination.Storage (Destination.Size) := 16#00#;

      else
         --  Data can't be stored "in place" and need to be converted into
         --  shared data.

         Copy_To_Heap
           (Data,
            VSS.Unicode.UTF8_Code_Unit_Count (Data.Capacity * 4),
            Destination.Size + L);

         declare
            Destination : UTF8_String_Data_Access
              with Import, Convention => Ada, Address => Data.Pointer'Address;

         begin
            Destination.Storage
              (From.UTF8_Offset + L .. Destination.Size + L) :=
               Destination.Storage (From.UTF8_Offset .. Destination.Size);

            VSS.Implementation.UTF8_Encoding.Unchecked_Store
              (Destination.Storage, From.UTF8_Offset, L, U1, U2, U3, U4);

            Destination.Size := Destination.Size + L;
            Destination.Length := Destination.Length + 1;
            Destination.Storage (Destination.Size) := 16#00#;
         end;
      end if;
   end Insert;

   --------------
   -- Is_Empty --
   --------------

   overriding function Is_Empty
     (Self : UTF8_String_Handler;
      Data : VSS.Implementation.Strings.String_Data) return Boolean
   is
      Destination : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      return Destination = null or else Destination.Length = 0;
   end Is_Empty;

   --------------
   -- Is_Empty --
   --------------

   overriding function Is_Empty
     (Self : UTF8_In_Place_String_Handler;
      Data : VSS.Implementation.Strings.String_Data) return Boolean
   is
      Destination : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      return Destination.Length = 0;
   end Is_Empty;

   ------------
   -- Length --
   ------------

   overriding function Length
     (Self : UTF8_String_Handler;
      Data : VSS.Implementation.Strings.String_Data)
      return VSS.Implementation.Strings.Character_Count
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      return (if Source = null then 0 else Source.Length);
   end Length;

   ------------
   -- Length --
   ------------

   overriding function Length
     (Self : UTF8_In_Place_String_Handler;
      Data : VSS.Implementation.Strings.String_Data)
      return VSS.Implementation.Strings.Character_Count
   is
      Source : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      return VSS.Implementation.Strings.Character_Count (Source.Length);
   end Length;

   ------------
   -- Mutate --
   ------------

   procedure Mutate
     (Data     : in out UTF8_String_Data_Access;
      Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count) is
   begin
      if Data = null then
         Data := Allocate (Capacity, Size);

      elsif not System.Atomic_Counters.Is_One (Data.Counter)
        or else Size > Data.Bulk
      then
         Reallocate (Data, Capacity, Size);
      end if;
   end Mutate;

   ---------------
   -- Normalize --
   ---------------

   overriding procedure Normalize
     (Self   : UTF8_String_Handler;
      Data   : VSS.Implementation.Strings.String_Data;
      Form   : VSS.Strings.Normalization_Form;
      Result : out VSS.Implementation.Strings.String_Data)
   is
      Source : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      if Source = null or else Source.Length = 0 then
         VSS.Implementation.String_Configuration.In_Place_Handler.Initialize
           (Result);

      else
         Self.Initialize (Result);

         case Form is
            when VSS.Strings.Normalization_Form_D =>
               Decomposite
                 (Source.Storage,
                  Source.Size,
                  VSS.Implementation.UCD_Normalization_UTF8.Canonical_Index,
                  Result);

            when VSS.Strings.Normalization_Form_C =>
               raise Program_Error;

            when VSS.Strings.Normalization_Form_KD =>
               raise Program_Error;

            when VSS.Strings.Normalization_Form_KC =>
               raise Program_Error;
         end case;
      end if;
   end Normalize;

   ---------------
   -- Normalize --
   ---------------

   overriding procedure Normalize
     (Self   : UTF8_In_Place_String_Handler;
      Data   : VSS.Implementation.Strings.String_Data;
      Form   : VSS.Strings.Normalization_Form;
      Result : out VSS.Implementation.Strings.String_Data)
   is
      Source : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      if Source.Length = 0 then
         VSS.Implementation.String_Configuration.In_Place_Handler.Initialize
           (Result);

      else
         Self.Initialize (Result);

         case Form is
            when VSS.Strings.Normalization_Form_D =>
               Decomposite
                 (Source.Storage,
                  Source.Size,
                  VSS.Implementation.UCD_Normalization_UTF8.Canonical_Index,
                  Result);

            when VSS.Strings.Normalization_Form_C =>
               raise Program_Error;

            when VSS.Strings.Normalization_Form_KD =>
               raise Program_Error;

            when VSS.Strings.Normalization_Form_KC =>
               raise Program_Error;
         end case;
      end if;
   end Normalize;

   ----------------
   -- Reallocate --
   ----------------

   procedure Reallocate
     (Data     : in out UTF8_String_Data_Access;
      Capacity : VSS.Unicode.UTF8_Code_Unit_Count;
      Size     : VSS.Unicode.UTF8_Code_Unit_Count)
   is
      Minimal_Capacity : constant VSS.Unicode.UTF8_Code_Unit_Count :=
        (if Capacity >= Size
         then Capacity
         else (if Data = null
               then Size
               else (if Data.Bulk > Size
                     then Size
                     else Size + Size / Growth_Factor)));

      Aux : UTF8_String_Data_Access := Data;

   begin
      Data := Allocate (0, Minimal_Capacity);

      if Aux /= null then
         declare
            Last : constant VSS.Unicode.UTF8_Code_Unit_Count :=
              VSS.Unicode.UTF8_Code_Unit_Count'Min (Data.Bulk, Aux.Bulk);

         begin
            Data.Storage (0 .. Last) := Aux.Storage (0 .. Last);
            Data.Size := Aux.Size;
            Data.Length := Aux.Length;
            Unreference (Aux);
         end;
      end if;
   end Reallocate;

   ---------------
   -- Reference --
   ---------------

   overriding procedure Reference
     (Self : UTF8_String_Handler;
      Data : in out VSS.Implementation.Strings.String_Data)
   is
      Destination : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      if Destination /= null then
         System.Atomic_Counters.Increment (Destination.Counter);
      end if;
   end Reference;

   -----------
   -- Slice --
   -----------

   overriding procedure Slice
     (Self        : UTF8_String_Handler;
      Source_Data : VSS.Implementation.Strings.String_Data;
      From        : VSS.Implementation.Strings.Cursor;
      To          : VSS.Implementation.Strings.Cursor;
      Target_Data : out VSS.Implementation.Strings.String_Data)
   is
      Source : constant UTF8_String_Data_Access
        with Import,
             Convention => Ada,
             Address    => Source_Data.Pointer'Address;

      Size   : VSS.Unicode.UTF8_Code_Unit_Count;
      Length : VSS.Implementation.Strings.Character_Count;
      After  : VSS.Implementation.Strings.Cursor := To;

   begin
      if From.Index > To.Index then
         Target_Data := VSS.Implementation.Strings.Null_String_Data;

         return;
      end if;

      Unchecked_Forward (Source.Storage, After);

      Size   := After.UTF8_Offset - From.UTF8_Offset;
      Length := After.Index - From.Index;

      if Size <= In_Place_Storage_Capacity
        and then
          VSS.Implementation.String_Configuration.In_Place_Handler.all
            in UTF8_In_Place_String_Handler
      then
         VSS.Implementation.String_Configuration.In_Place_Handler.Initialize
           (Target_Data);

         Unchecked_Append
           (Target_Data, Source.Storage, From.UTF8_Offset, Size, Length);

      elsif Size > In_Place_Storage_Capacity then
         Self.Initialize (Target_Data);

         Unchecked_Append
           (Target_Data, Source.Storage, From.UTF8_Offset, Size, Length);

      else
         VSS.Implementation.String_Handlers.Abstract_String_Handler
           (Self).Slice (Source_Data, From, To, Target_Data);
      end if;
   end Slice;

   -----------
   -- Slice --
   -----------

   overriding procedure Slice
     (Self        : UTF8_In_Place_String_Handler;
      Source_Data : VSS.Implementation.Strings.String_Data;
      From        : VSS.Implementation.Strings.Cursor;
      To          : VSS.Implementation.Strings.Cursor;
      Target_Data : out VSS.Implementation.Strings.String_Data)
   is
      Source : constant UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Source_Data'Address;

      Size   : VSS.Unicode.UTF8_Code_Unit_Count;
      Length : VSS.Implementation.Strings.Character_Count;
      After  : VSS.Implementation.Strings.Cursor := To;

   begin
      if From.Index > To.Index then
         Target_Data := VSS.Implementation.Strings.Null_String_Data;

         return;
      end if;

      Unchecked_Forward (Source.Storage, After);

      Size   := After.UTF8_Offset - From.UTF8_Offset;
      Length := After.Index - From.Index;

      Self.Initialize (Target_Data);

      Unchecked_Append
        (Target_Data, Source.Storage, From.UTF8_Offset, Size, Length);
   end Slice;

   -----------------
   -- Split_Lines --
   -----------------

   overriding procedure Split_Lines
     (Self            : UTF8_String_Handler;
      Data            : VSS.Implementation.Strings.String_Data;
      Terminators     : VSS.Strings.Line_Terminator_Set;
      Keep_Terminator : Boolean;
      Lines           : in out
        VSS.Implementation.String_Vectors.String_Vector_Data_Access)
   is
      Source : constant UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      Split_Lines_Common
        (Handler         => Self,
         Data            => Data,
         Storage         => Source.Storage,
         Terminators     => Terminators,
         Keep_Terminator => Keep_Terminator,
         Lines           => Lines);
   end Split_Lines;

   -----------------
   -- Split_Lines --
   -----------------

   overriding procedure Split_Lines
     (Self            : UTF8_In_Place_String_Handler;
      Data            : VSS.Implementation.Strings.String_Data;
      Terminators     : VSS.Strings.Line_Terminator_Set;
      Keep_Terminator : Boolean;
      Lines           : in out
        VSS.Implementation.String_Vectors.String_Vector_Data_Access)
   is
      Source : constant UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      Split_Lines_Common
        (Handler         => Self,
         Data            => Data,
         Storage         => Source.Storage,
         Terminators     => Terminators,
         Keep_Terminator => Keep_Terminator,
         Lines           => Lines);
   end Split_Lines;

   ------------------------
   -- Split_Lines_Common --
   ------------------------

   procedure Split_Lines_Common
     (Handler         :
        VSS.Implementation.String_Handlers.Abstract_String_Handler'Class;
      Data            : VSS.Implementation.Strings.String_Data;
      Storage         : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Terminators     : VSS.Strings.Line_Terminator_Set;
      Keep_Terminator : Boolean;
      Lines           : in out
        VSS.Implementation.String_Vectors.String_Vector_Data_Access)
   is
      procedure Append
        (Source_Storage :
           VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
         First          : VSS.Implementation.Strings.Cursor;
         After_Last     : VSS.Implementation.Strings.Cursor);

      ------------
      -- Append --
      ------------

      procedure Append
        (Source_Storage :
           VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
         First          : VSS.Implementation.Strings.Cursor;
         After_Last     : VSS.Implementation.Strings.Cursor)
      is
         Size : constant VSS.Unicode.UTF8_Code_Unit_Count :=
           After_Last.UTF8_Offset - First.UTF8_Offset;
         Data : VSS.Implementation.Strings.String_Data;

      begin
         if Size = 0 then
            Data :=
              (In_Place => False,
               Padding  => False,
               Capacity => 0,
               Handler  => null,
               Pointer  => System.Null_Address);

         elsif Size <= In_Place_Storage_Capacity
           and then
             VSS.Implementation.String_Configuration.In_Place_Handler.all
               in UTF8_In_Place_String_Handler
         then
            --  Inplace handler is known, use it for short strings.

            Data :=
              (In_Place => True,
               Padding  => False,
               Capacity => 0,
               Storage  => <>);

            declare
               Destination : UTF8_In_Place_Data
                 with Import,
                      Convention => Ada,
                      Address    => Data.Storage'Address;

            begin
               Destination.Storage (0 .. Size - 1) :=
                 Source_Storage
                   (First.UTF8_Offset .. After_Last.UTF8_Offset - 1);
               Destination.Storage (Size) := 0;
               Destination.Size := Size;
               Destination.Length := After_Last.Index - First.Index;
            end;

         else
            Data :=
              (In_Place => False,
               Padding  => False,
               Capacity => 0,
               Handler  => Global_UTF8_String_Handler'Unrestricted_Access,
               Pointer  => System.Null_Address);

            declare
               Destination : UTF8_String_Data_Access
                 with Import,
                      Convention => Ada,
                      Address    => Data.Pointer'Address;

            begin
               Destination := Allocate (0, Size);

               Destination.Storage (0 .. Size - 1) :=
                 Source_Storage
                   (First.UTF8_Offset .. After_Last.UTF8_Offset - 1);
               Destination.Storage (Size) := 0;
               Destination.Size := Size;
               Destination.Length := After_Last.Index - First.Index;
            end;
         end if;

         VSS.Implementation.String_Vectors.Append_And_Move_Ownership
           (Lines, Data);
      end Append;

      Initial    : VSS.Implementation.Strings.Cursor;
      At_First   : VSS.Implementation.Strings.Cursor;
      At_Last    : VSS.Implementation.Strings.Cursor;
      After_Last : VSS.Implementation.Strings.Cursor;
      Terminator : VSS.Implementation.Strings.Cursor;
      Dummy      : Boolean;

   begin
      VSS.Implementation.String_Vectors.Unreference (Lines);

      Handler.Before_First_Character (Data, Initial);

      while VSS.Implementation.Line_Iterators.Forward
        (Data,
         Terminators,
         Initial,
         At_First,
         At_Last,
         Terminator)
      loop
         Initial := At_Last;

         if VSS.Implementation.Strings.Is_Invalid (Terminator) then
            After_Last := At_Last;
            Dummy      := Handler.Forward (Data, After_Last);

         elsif Keep_Terminator then
            After_Last := At_Last;
            Dummy      := Handler.Forward (Data, After_Last);

         else
            After_Last := Terminator;
         end if;

         Append (Storage, At_First, After_Last);
      end loop;
   end Split_Lines_Common;

   ---------------------
   -- To_UTF_8_String --
   ---------------------

   overriding function To_UTF_8_String
     (Self : UTF8_String_Handler;
      Data : VSS.Implementation.Strings.String_Data)
      return Ada.Strings.UTF_Encoding.UTF_8_String
   is
      Destination : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      return Result : Ada.Strings.UTF_Encoding.UTF_8_String
        (1 .. (if Destination = null then 0 else Natural (Destination.Size)))
      do
         for J in Result'Range loop
            Result (J) :=
              Standard.Character'Val
                (Destination.Storage
                   (VSS.Unicode.UTF8_Code_Unit_Count (J - 1)));
         end loop;
      end return;
   end To_UTF_8_String;

   ---------------------
   -- To_UTF_8_String --
   ---------------------

   overriding function To_UTF_8_String
     (Self : UTF8_In_Place_String_Handler;
      Data : VSS.Implementation.Strings.String_Data)
      return Ada.Strings.UTF_Encoding.UTF_8_String
   is
      Destination : UTF8_In_Place_Data
        with Import, Convention => Ada, Address => Data'Address;

   begin
      return Result : Ada.Strings.UTF_Encoding.UTF_8_String
                        (1 .. Natural (Destination.Size))
      do
         for J in Result'Range loop
            Result (J) :=
              Standard.Character'Val
                (Destination.Storage
                   (VSS.Unicode.UTF8_Code_Unit_Count (J - 1)));
         end loop;
      end return;
   end To_UTF_8_String;

   ----------------------
   -- Unchecked_Append --
   ----------------------

   procedure Unchecked_Append
     (Target_Data : in out VSS.Implementation.Strings.String_Data;
      Target_Size : out VSS.Unicode.UTF8_Code_Unit_Count;
      Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      From        : VSS.Unicode.UTF8_Code_Unit_Index;
      Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Length      : VSS.Implementation.Strings.Character_Count) is
   begin
      if Target_Data.In_Place then
         declare
            Target : UTF8_In_Place_Data
              with Import, Convention => Ada, Address => Target_Data'Address;

         begin
            if Target.Size + Size <= In_Place_Storage_Capacity then
               Target.Storage (Target.Size .. Target.Size + Size - 1) :=
                 Storage (From .. From + Size - 1);
               Target.Size   := Target.Size + Size;
               Target.Length := Target.Length + Length;

               Target_Size   := Target.Size;

               return;

            else
               Copy_To_Heap (Target_Data, 0, Target.Size + Size);
            end if;
         end;
      end if;

      declare
         Target : UTF8_String_Data_Access
           with Import, Convention => Ada,
                Address => Target_Data.Pointer'Address;

      begin
         if Target = null then
            Target := Allocate (0, Size);

         elsif Target.Size + Size > Target.Bulk then
            Reallocate (Target, 0, Target.Size + Size);
         end if;

         Target.Storage (Target.Size .. Target.Size + Size - 1) :=
           Storage (From .. From + Size - 1);
         Target.Size   := Target.Size + Size;
         Target.Length := Target.Length + Length;

         Target_Size   := Target.Size;
      end;
   end Unchecked_Append;

   ----------------------
   -- Unchecked_Append --
   ----------------------

   procedure Unchecked_Append
     (Target_Data : in out VSS.Implementation.Strings.String_Data;
      Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      From        : VSS.Unicode.UTF8_Code_Unit_Index;
      Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Length      : VSS.Implementation.Strings.Character_Count)
   is
      Target_Size : VSS.Unicode.UTF8_Code_Unit_Count;

   begin
      Unchecked_Append (Target_Data, Target_Size, Storage, From, Size, Length);
   end Unchecked_Append;

   ------------------------
   -- Unchecked_Backward --
   ------------------------

   procedure Unchecked_Backward
     (Storage  : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Position : in out VSS.Implementation.Strings.Cursor) is
   begin
      Position.Index        := Position.Index - 1;
      Position.UTF8_Offset  := Position.UTF8_Offset - 1;
      Position.UTF16_Offset := Position.UTF16_Offset - 1;

      if Position.Index /= 0 then
         loop
            declare
               Code : constant VSS.Unicode.UTF8_Code_Unit :=
                 Storage (Position.UTF8_Offset);

            begin
               case Code is
                  when 16#80# .. 16#BF# =>
                     Position.UTF8_Offset  := Position.UTF8_Offset - 1;

                  when 16#00# .. 16#7F#
                     | 16#C2# .. 16#DF#
                     | 16#E0# .. 16#EF# =>

                     exit;

                  when 16#F0# .. 16#F4# =>
                     Position.UTF16_Offset := Position.UTF16_Offset - 1;
                     exit;

                  when others =>
                     raise Program_Error with "string data is corrupted";
               end case;
            end;
         end loop;
      end if;
   end Unchecked_Backward;

   -------------------------------
   -- Unchecked_Backward_Decode --
   -------------------------------

   procedure Unchecked_Backward_Decode
     (Source_Data : VSS.Implementation.Strings.String_Data;
      Offset      : in out VSS.Unicode.UTF8_Code_Unit_Index;
      Code        : out VSS.Unicode.Code_Point) is
   begin
      if Source_Data.In_Place then
         declare
            Source : UTF8_In_Place_Data
              with Import, Convention => Ada, Address => Source_Data'Address;

         begin
            Unchecked_Backward_Decode (Source.Storage, Offset, Code);
         end;

      else
         declare
            Source : UTF8_String_Data_Access
              with Import, Convention => Ada,
                   Address => Source_Data.Pointer'Address;

         begin
            Unchecked_Backward_Decode (Source.Storage, Offset, Code);
         end;
      end if;
   end Unchecked_Backward_Decode;

   -------------------------------
   -- Unchecked_Backward_Decode --
   -------------------------------

   procedure Unchecked_Backward_Decode
     (Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Offset  : in out VSS.Unicode.UTF8_Code_Unit_Index;
      Code    : out VSS.Unicode.Code_Point) is
   begin
      Offset := Offset - 1;

      loop
         declare
            Code : constant VSS.Unicode.UTF8_Code_Unit := Storage (Offset);

         begin
            case Code is
               when 16#80# .. 16#BF# =>
                  Offset  := Offset - 1;

               when 16#00# .. 16#7F#
                  | 16#C2# .. 16#DF#
                  | 16#E0# .. 16#EF# =>

                  exit;

               when 16#F0# .. 16#F4# =>
                  exit;

               when others =>
                  raise Program_Error with "string data is corrupted";
            end case;
         end;
      end loop;

      Code := Unchecked_Decode (Storage, Offset);
   end Unchecked_Backward_Decode;

   ----------------------
   -- Unchecked_Decode --
   ----------------------

   function Unchecked_Decode
     (Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Offset  : VSS.Unicode.UTF8_Code_Unit_Index)
      return VSS.Unicode.Code_Point
   is
      use type VSS.Unicode.Code_Point;
      use type VSS.Unicode.UTF8_Code_Unit;

      U1 : VSS.Unicode.Code_Point := VSS.Unicode.Code_Point (Storage (Offset));
      U2 : VSS.Unicode.Code_Point;
      U3 : VSS.Unicode.Code_Point;
      U4 : VSS.Unicode.Code_Point;

   begin
      case U1 is
         when 16#00# .. 16#7F# =>
            --  1x code units sequence

            return U1;

         when 16#C2# .. 16#DF# =>
            --  2x code units sequence

            U1 := (U1 and 2#0001_1111#) * 2#0100_0000#;
            U2 :=
              VSS.Unicode.Code_Point (Storage (Offset + 1) and 2#0011_1111#);

            return U1 or U2;

         when 16#E0# .. 16#EF# =>
            --  3x code units sequence

            U1 := (U1 and 2#0000_1111#) * 2#01_0000_0000_0000#;
            U2 := VSS.Unicode.Code_Point
              (Storage (Offset + 1) and 2#0011_1111#) * 2#0100_0000#;
            U3 :=
              VSS.Unicode.Code_Point (Storage (Offset + 2) and 2#0011_1111#);

            return U1 or U2 or U3;

         when 16#F0# .. 16#F4# =>
            --  4x code units sequence

            U1 := (U1 and 2#0000_0111#) * 2#0100_0000_0000_0000_0000#;
            U2 := VSS.Unicode.Code_Point
              (Storage (Offset + 1) and 2#0011_1111#) * 2#010_000_0000_0000#;
            U3 :=
              VSS.Unicode.Code_Point
                (Storage (Offset + 2) and 2#0011_1111#) * 2#0100_0000#;
            U4 :=
              VSS.Unicode.Code_Point (Storage (Offset + 3) and 2#0011_1111#);

            return U1 or U2 or U3 or U4;

         when others =>
            raise Program_Error;
      end case;
   end Unchecked_Decode;

   ------------------------------
   -- Unchecked_Decode_Forward --
   ------------------------------

   procedure Unchecked_Decode_Forward
     (Storage : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Offset  : in out VSS.Unicode.UTF8_Code_Unit_Index;
      Code    : out VSS.Unicode.Code_Point)
   is
      use type VSS.Unicode.Code_Point;
      use type VSS.Unicode.UTF8_Code_Unit;

      U1 : VSS.Unicode.Code_Point := VSS.Unicode.Code_Point (Storage (Offset));
      U2 : VSS.Unicode.Code_Point;
      U3 : VSS.Unicode.Code_Point;
      U4 : VSS.Unicode.Code_Point;

   begin
      case U1 is
         when 16#00# .. 16#7F# =>
            --  1x code units sequence

            Code   := U1;
            Offset := Offset + 1;

         when 16#C2# .. 16#DF# =>
            --  2x code units sequence

            U1 := (U1 and 2#0001_1111#) * 2#0100_0000#;
            U2 :=
              VSS.Unicode.Code_Point (Storage (Offset + 1) and 2#0011_1111#);

            Code   := U1 or U2;
            Offset := Offset + 2;

         when 16#E0# .. 16#EF# =>
            --  3x code units sequence

            U1 := (U1 and 2#0000_1111#) * 2#01_0000_0000_0000#;
            U2 := VSS.Unicode.Code_Point
              (Storage (Offset + 1) and 2#0011_1111#) * 2#0100_0000#;
            U3 :=
              VSS.Unicode.Code_Point (Storage (Offset + 2) and 2#0011_1111#);

            Code   := U1 or U2 or U3;
            Offset := Offset + 3;

         when 16#F0# .. 16#F4# =>
            --  4x code units sequence

            U1 := (U1 and 2#0000_0111#) * 2#0100_0000_0000_0000_0000#;
            U2 := VSS.Unicode.Code_Point
              (Storage (Offset + 1) and 2#0011_1111#) * 2#010_000_0000_0000#;
            U3 :=
              VSS.Unicode.Code_Point
                (Storage (Offset + 2) and 2#0011_1111#) * 2#0100_0000#;
            U4 :=
              VSS.Unicode.Code_Point (Storage (Offset + 3) and 2#0011_1111#);

            Code   := U1 or U2 or U3 or U4;
            Offset := Offset + 4;

         when others =>
            raise Program_Error;
      end case;
   end Unchecked_Decode_Forward;

   -----------------------
   -- Unchecked_Forward --
   -----------------------

   procedure Unchecked_Forward
     (Storage  : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Position : in out VSS.Implementation.Strings.Cursor) is
   begin
      Position.Index := Position.Index + 1;

      if Position.Index = 1 then
         Position.UTF8_Offset  := Position.UTF8_Offset + 1;
         Position.UTF16_Offset := Position.UTF16_Offset + 1;

         return;
      end if;

      declare
         Code : constant VSS.Unicode.UTF8_Code_Unit :=
           Storage (Position.UTF8_Offset);

      begin
         case Code is
            when 16#00# .. 16#7F# =>
               Position.UTF8_Offset  := Position.UTF8_Offset + 1;
               Position.UTF16_Offset := Position.UTF16_Offset + 1;

            when 16#C2# .. 16#DF# =>
               Position.UTF8_Offset  := Position.UTF8_Offset + 2;
               Position.UTF16_Offset := Position.UTF16_Offset + 1;

            when 16#E0# .. 16#EF# =>
               Position.UTF8_Offset  := Position.UTF8_Offset + 3;
               Position.UTF16_Offset := Position.UTF16_Offset + 1;

            when 16#F0# .. 16#F4# =>
               Position.UTF8_Offset  := Position.UTF8_Offset + 4;
               Position.UTF16_Offset := Position.UTF16_Offset + 2;

            when others =>
               raise Program_Error with "string data is corrupted";
         end case;
      end;

      --  XXX case statement above may be rewritten as below to avoid
      --  use of branch instructions.
      --
      --  Position.UTF8_Offset  :=
      --    Position.UTF8_Offset + 1
      --      + (if (Code and 2#1000_0000#) = 2#1000_0000# then 1 else 0)
      --      + (if (Code and 2#1110_0000#) = 2#1110_0000# then 1 else 0)
      --      + (if (Code and 2#1111_0000#) = 2#1111_0000# then 1 else 0);
      --
      --  Position.UTF16_Offset :=
      --    Position.UTF16_Offset + 1
      --      + (if (Code and 2#1111_0000#) = 2#1111_0000# then 1 else 0);
   end Unchecked_Forward;

   ----------------------
   -- Unchecked_Insert --
   ----------------------

   procedure Unchecked_Insert
     (Target_Data : in out VSS.Implementation.Strings.String_Data;
      Target_Size : out VSS.Unicode.UTF8_Code_Unit_Count;
      Into        : VSS.Unicode.UTF8_Code_Unit_Index;
      Storage     : VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      From        : VSS.Unicode.UTF8_Code_Unit_Index;
      Size        : VSS.Unicode.UTF8_Code_Unit_Count;
      Length      : VSS.Implementation.Strings.Character_Count) is
   begin
      if Target_Data.In_Place then
         declare
            Target : UTF8_In_Place_Data
              with Import, Convention => Ada, Address => Target_Data'Address;

         begin
            if Target.Size + Size <= In_Place_Storage_Capacity then
               Target.Storage (Into + Size .. Target.Size + Size - 1) :=
                 Target.Storage (Into .. Target.Size - 1);
               Target.Storage (Into .. Into + Size - 1) :=
                 Storage (From .. From + Size - 1);
               Target.Size   := Target.Size + Size;
               Target.Length := Target.Length + Length;

               Target_Size   := Target.Size;

            else
               raise Program_Error;
            end if;
         end;

      else
         declare
            Target : UTF8_String_Data_Access
              with Import, Convention => Ada,
                   Address => Target_Data.Pointer'Address;

         begin
            if Target = null then
               Target := Allocate (0, Size);

            elsif Target.Size + Size > Target.Bulk then
               --  Reallocate (Target, 0, Target.Size + Size);
               raise Program_Error;
            end if;

            raise Program_Error;
            --  Target.Storage (Target.Size .. Target.Size + Size - 1) :=
            --    Storage (From .. From + Size - 1);
            --  Target.Size := Target.Size + Size;
            --  Target.Length := Target.Length + Length;
         end;
      end if;
   end Unchecked_Insert;

   -----------------
   -- Unreference --
   -----------------

   procedure Unreference (Data : in out UTF8_String_Data_Access) is
      procedure Free is
        new Ada.Unchecked_Deallocation
              (UTF8_String_Data, UTF8_String_Data_Access);

   begin
      if Data /= null then
         if System.Atomic_Counters.Decrement (Data.Counter) then
            Free (Data);

         else
            Data := null;
         end if;
      end if;
   end Unreference;

   -----------------
   -- Unreference --
   -----------------

   overriding procedure Unreference
     (Self : UTF8_String_Handler;
      Data : in out VSS.Implementation.Strings.String_Data)
   is
      Destination : UTF8_String_Data_Access
        with Import, Convention => Ada, Address => Data.Pointer'Address;

   begin
      Unreference (Destination);
   end Unreference;

   -----------------------
   -- Validate_And_Copy --
   -----------------------

   procedure Validate_And_Copy
     (Source      : Ada.Strings.UTF_Encoding.UTF_8_String;
      Destination : out VSS.Implementation.UTF8_Encoding.UTF8_Code_Unit_Array;
      Length      : out VSS.Implementation.Strings.Character_Count;
      Success     : out Boolean)
   is
      State : Verification_State := Initial;
      Code  : VSS.Unicode.UTF8_Code_Unit;

   begin
      Length := 0;

      for J in Source'Range loop
         Code := Standard.Character'Pos (Source (J));

         case State is
            when Initial =>
               Length := Length + 1;

               case Code is
                  when 16#00# .. 16#7F# =>
                     null;

                  when 16#C2# .. 16#DF# =>
                     State := UT1;

                  when 16#E0# =>
                     State := U31;

                  when 16#E1# .. 16#EC# =>
                     State := UT2;

                  when 16#ED# =>
                     State := U33;

                  when 16#EE# .. 16#EF# =>
                     State := UT2;

                  when 16#F0# =>
                     State := U41;

                  when 16#F1# .. 16#F3# =>
                     State := UT3;

                  when 16#F4# =>
                     State := U43;

                  when others =>
                     State := Ill_Formed;
               end case;

            when U31 =>
               case Code is
                  when 16#A0# .. 16#BF# =>
                     State := UT1;

                  when others =>
                     State := Ill_Formed;
               end case;

            when U33 =>
               case Code is
                  when 16#80# .. 16#9F# =>
                     State := UT1;

                  when others =>
                     State := Ill_Formed;
               end case;

            when U41 =>
               case Code is
                  when 16#90# .. 16#BF# =>
                     State := UT2;

                  when others =>
                     State := Ill_Formed;
               end case;

            when U43 =>
               case Code is
                  when 16#80# .. 16#8F# =>
                     State := UT2;

                  when others =>
                     State := Ill_Formed;
               end case;

            when UT1 =>
               case Code is
                  when 16#80# .. 16#BF# =>
                     State := Initial;

                  when others =>
                     State := Ill_Formed;
               end case;

            when UT2 =>
               case Code is
                  when 16#80# .. 16#BF# =>
                     State := UT1;

                  when others =>
                     State := Ill_Formed;
               end case;

            when UT3 =>
               case Code is
                  when 16#80# .. 16#BF# =>
                     State := UT2;

                  when others =>
                     State := Ill_Formed;
               end case;

            when Ill_Formed =>
               exit;
         end case;

         Destination
           (VSS.Unicode.UTF8_Code_Unit_Count (J - Source'First)) := Code;
      end loop;

      Success := State = Initial;
   end Validate_And_Copy;

end VSS.Implementation.UTF8_String_Handlers;
