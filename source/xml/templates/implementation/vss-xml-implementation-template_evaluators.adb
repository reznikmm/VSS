--
--  Copyright (C) 2022, AdaCore
--
--  SPDX-License-Identifier: Apache-2.0
--

pragma Warnings (Off);
pragma Ada_2020;
pragma Ada_2022;
pragma Warnings (On);

with Ada.Unchecked_Deallocation;

with VSS.XML.Attributes.Containers;
with VSS.XML.Implementation.Parse_Errors;
with VSS.XML.Implementation.Template_Programs.Debug;
with VSS.XML.Templates.Proxies;
with VSS.XML.Templates.Values;

--  with Ada.Wide_Wide_Text_IO; use Ada.Wide_Wide_Text_IO;
--  with VSS.Strings.Conversions; use VSS.Strings.Conversions;

package body VSS.XML.Implementation.Template_Evaluators is

   -----------
   -- Error --
   -----------

   overriding procedure Error
     (Self    : in out Template_Evaluator;
      Message : VSS.Strings.Virtual_String;
      Success : in out Boolean)
   is
      Error :
        constant VSS.XML.Implementation.Parse_Errors.Parse_Error_Location :=
        (Public_Id => <>,
         System_Id => Self.Current.System_Id,
         Line      => Self.Current.Line,
         Column    => Self.Current.Column,
         Message   => Message);

   begin
      Self.Error.Error (Error, Success);
   end Error;

   --------------
   -- Evaluate --
   --------------

   procedure Evaluate
     (Self    : in out Template_Evaluator'Class;
      Binded  :
        not null VSS.XML.Implementation.Template_Namespaces.Namespace_Access;
      Program :
        VSS.XML.Implementation.Template_Programs.Instruction_Vectors.Vector;
      Success : in out Boolean)
   is
      use type VSS.XML.Content_Handlers.SAX_Content_Handler_Access;
      use type VSS.XML.Implementation.Template_Programs.Address;
      use all type VSS.XML.Implementation.Template_Programs.Instruction_Kind;

      procedure Do_Start_Element
        (Current : in out VSS.XML.Implementation.Template_Programs.Address);

      procedure Do_Content
        (Instruction : VSS.XML.Implementation.Template_Programs.Instruction);

      procedure Do_Repeat
        (Instruction : VSS.XML.Implementation.Template_Programs.Instruction);

      procedure Execute
        (Current : in out VSS.XML.Implementation.Template_Programs.Address);

      procedure Push_State;
      procedure Pop_State;

      ----------------
      -- Do_Content --
      ----------------

      procedure Do_Content
        (Instruction : VSS.XML.Implementation.Template_Programs.Instruction) is
      begin
         Push_State;
         --  if Self.Current.Element
         --    /= VSS.XML.Implementation.Template_Programs.Null_Address
         --  then
         --     raise Program_Error;
         --  end if;

         Self.Current.Content := Instruction.Content_Path;
      end Do_Content;

      ---------------
      -- Do_Repeat --
      ---------------

      procedure Do_Repeat
        (Instruction : VSS.XML.Implementation.Template_Programs.Instruction)
      is
         use type
           VSS.XML.Implementation.Template_Namespaces.Iterable_Iterator_Access;
         use type VSS.XML.Error_Handlers.SAX_Error_Handler_Access;

         Iterator :
           VSS.XML.Implementation.Template_Namespaces.Iterable_Iterator_Access;

      begin
         Iterator :=
           Self.Current.Namespace.Resolve_Iterable
             (Instruction.Repeat_Path);

         if Iterator = null then
            if Self.Error /= null then
               declare
                  Error : constant
                    VSS.XML.Implementation.Parse_Errors.Parse_Error_Location :=
                      (Public_Id => <>,
                       System_Id => Self.Current.System_Id,
                       Line      => Self.Current.Line,
                       Column    => Self.Current.Column,
                       Message   => "Unable to resolve path to iterable");

               begin
                  Self.Error.Error (Error, Success);
               end;
            end if;

         else
            Push_State;

            Self.Current.Iterator := Iterator;
            Self.Current.Namespace.Bind
              (Instruction.Identifier,
               VSS.XML.Templates.Proxies.Proxy_Access (Iterator));
         end if;
      end Do_Repeat;

      ----------------------
      -- Do_Start_Element --
      ----------------------

      procedure Do_Start_Element
        (Current : in out VSS.XML.Implementation.Template_Programs.Address)
      is
         use type
           VSS.XML.Implementation.Template_Namespaces.Iterable_Iterator_Access;

         Element     :
           constant VSS.XML.Implementation.Template_Programs.Address :=
             Current;
         Instruction : VSS.XML.Implementation.Template_Programs.Instruction
           renames Program (Current);
         Attributes  : VSS.XML.Attributes.Containers.Attributes;

      begin
         if Self.Current.Element =
           VSS.XML.Implementation.Template_Programs.Null_Address
         then
            Self.Current.Element := Current;
         end if;

         if Self.Current.Element = Current
           and then Self.Current.Iterator /= null
           and then not Self.Current.Iterator.Next
         then
            --  Rewind till end of the element.

            loop
               Current := @ + 1;

               exit when Current > Program.Last_Index;

               exit when Program (Current).Kind = End_Element
                 and then Program (Current).Start_Address
                            = Self.Current.Element;
            end loop;

            Pop_State;

         else
            --  Process attributes

            loop
               Current := @ + 1;

               exit when Current > Program.Last_Index;
               exit when Program (Current).Kind /= Attribute;

               if Program (Current).Attribute_Path.Is_Empty then
                  Attributes.Insert
                    (Program (Current).Attribute_URI,
                     Program (Current).Attribute_Name,
                     Program (Current).Attribute_Value);

               else
                  declare
                     use type VSS.XML.Templates.Values.Value_Kind;

                     V : constant VSS.XML.Templates.Values.Value :=
                       Self.Current.Namespace.Resolve_Value
                         (Program (Current).Attribute_Path);

                  begin
                     if V.Kind = VSS.XML.Templates.Values.String then
                        Attributes.Insert
                          (Program (Current).Attribute_URI,
                           Program (Current).Attribute_Name,
                           V.String_Value);

                     else
                        raise Program_Error;
                     end if;
                  end;
               end if;
            end loop;

            Current := @ - 1;

            if Self.Content /= null then
               Self.Content.Start_Element
                 (Instruction.URI,
                  Instruction.Name,
                  Attributes,
                  Success);
            end if;

            if Self.Current.Element = Element
              and then not Self.Current.Content.Is_Empty
            then
               if Self.Content /= null then
                  Self.Content.Characters
                    (Self.Current.Namespace.Resolve_Content
                       (Self.Current.Content, Self, Success),
                     Success);
               end if;

               --  Rewind till end of the element.

               loop
                  Current := @ + 1;

                  exit when Current > Program.Last_Index;

                  if Program (Current).Kind = End_Element
                    and then Program (Current).Start_Address
                               = Self.Current.Element
                  then
                     Current := @ - 1;

                     exit;
                  end if;
               end loop;
            end if;
         end if;
      end Do_Start_Element;

      -------------
      -- Execute --
      -------------

      procedure Execute
        (Current : in out VSS.XML.Implementation.Template_Programs.Address)
      is
         use type
           VSS.XML.Implementation.Template_Namespaces.Iterable_Iterator_Access;

         Instruction : VSS.XML.Implementation.Template_Programs.Instruction
           renames Program (Current);

      begin
         case Instruction.Kind is
            when Start_Element =>
               Do_Start_Element (Current);

            when Attribute =>
               --  Attribute instructions are processed together with
               --  Start_Element instruction.

               raise Program_Error;

            when End_Element =>
               if Self.Content /= null then
                  Self.Content.End_Element
                    (Program (Instruction.Start_Address).URI,
                     Program (Instruction.Start_Address).Name,
                     Success);

                  --  exit when not Success;
               end if;

               if Self.Current.Element = Instruction.Start_Address then
                  if Self.Current.Iterator /= null then
                     Current := Self.Current.Element - 1;

                  else
                     Pop_State;
                  end if;

                  --  raise Program_Error;
               end if;

            when Text =>
               if Self.Content /= null then
                  Self.Content.Characters (Instruction.Text, Success);

                  --  exit when not Success;
               end if;

            when Location =>
               Push_State;

               Self.Current.System_Id := Instruction.System_Id;
               Self.Current.Line      := Instruction.Line;
               Self.Current.Column    := Instruction.Column;

            when Content =>
               Do_Content (Program (Current));

            when Repeat =>
               Do_Repeat (Program (Current));

            when Done =>
               --  exit;
               null;

            when others =>
               raise Program_Error with Instruction.Kind'Image;
         end case;

         Current := @ + 1;
      end Execute;

      ---------------
      -- Pop_State --
      ---------------

      procedure Pop_State is
         procedure Free is
           new Ada.Unchecked_Deallocation
             (VSS.XML.Implementation.Template_Namespaces.Namespace'Class,
              VSS.XML.Implementation.Template_Namespaces.Namespace_Access);

      begin
         Free (Self.Current.Namespace);
         Self.Current := Self.Stack.Last_Element;
         Self.Stack.Delete_Last;
      end Pop_State;

      ----------------
      -- Push_State --
      ----------------

      procedure Push_State is
      begin
         if Self.Current.Element
           = VSS.XML.Implementation.Template_Programs.Null_Address
         then
            --  Start_Element event has not been processed, continue to
            --  build context for following Start_Element even.

            return;
         end if;

         Self.Stack.Append (Self.Current);
         Self.Current :=
           (Element   =>
              VSS.XML.Implementation.Template_Programs.Null_Address,
            Namespace =>
               new VSS.XML.Implementation.Template_Namespaces.Namespace'
                     (Ada.Finalization.Limited_Controlled with
                        Enclosing => Self.Current.Namespace,
                        others    => <>),
            Iterator  => null,
            Content   => VSS.String_Vectors.Empty_Virtual_String_Vector,
            System_Id => <>,
            Line      => 0,
            Column    => 0);
      end Push_State;

      Current : VSS.XML.Implementation.Template_Programs.Address :=
        Program.First_Index;

   begin
      Template_Programs.Debug.Dump (Program);
      Self.Current.Namespace :=
        new VSS.XML.Implementation.Template_Namespaces.Namespace'
              (Ada.Finalization.Limited_Controlled with
                 Enclosing => Binded,
                 others    => <>);
      Self.Current.Element :=
        VSS.XML.Implementation.Template_Programs.Address'Last;

      while Current <= Program.Last_Index loop
         Execute (Current);
      end loop;
   end Evaluate;

   --  ----------------------
   --  -- Resolve_Iterable --
   --  ----------------------
   --
   --  overriding function Resolve_Iterable
   --    (Self : Namespace;
   --     Path : VSS.String_Vectors.Virtual_String_Vector) return Cursor_Access
   --  is
   --     pragma Assert (not Path.Is_Empty);
   --
   --     Position : constant Named_Item_Maps.Cursor :=
   --       Self.Items.Find (Path (1));
   --     Subpath  : constant VSS.String_Vectors.Virtual_String_Vector :=
   --       Path.Delete_First;
   --
   --  begin
   --     return Result : Cursor_Access do
   --        if Named_Item_Maps.Has_Element (Position) then
   --           declare
   --              Item : constant not null Named_Item_Access :=
   --                Named_Item_Maps.Element (Position);
   --
   --           begin
   --              if Subpath.Is_Empty then
   --                 if Item.all in Iterable_Item'Class then
   --                    Result :=
   --                      new Iterable_Cursor'Class'
   --                            (Iterable_Item'Class (Item.all).Iterator);
   --                 end if;
   --
   --              elsif Item.all in Abstract_Namespace'Class then
   --                 Result :=
   --                   Abstract_Namespace'Class
   --                     (Item.all).Resolve_Iterable (Subpath);
   --              end if;
   --           end;
   --
   --        elsif Self.Enclosing /= null then
   --           Result := Self.Enclosing.Resolve_Iterable (Path);
   --        end if;
   --     end return;
   --  end Resolve_Iterable;

end VSS.XML.Implementation.Template_Evaluators;