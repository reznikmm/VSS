--
--  Copyright (C) 2023, AdaCore
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--

--  This package provides string template processor to substitute placeholders
--  by the text generated by given set of formatters.
--
--  String template placeholder has following format:
--    {[<parameter>][,<alignment>][:<format>]}
--
--  <parameter> is index of the parameter, when omitted next positional
--  parameter is used.
--
--  <alignment> specify width of the text in grapheme clusters and alignment:
--    [<^>][0-9]*
--
--    <      - left alignment
--    ^      - center alignment
--    >      - right alignment
--    [0-9]* - number of grapheme clusters to reserve for field
--
--  Default alignment depends from the formatter. If string returned by the
--  formatter is longer than reserved width it is put into output without
--  truncation.
--
--  <format> format of the data to be passed to formatter. It is processed by
--  the formatters, see documentation for particular formatter.

with VSS.Strings.Formatters;

package VSS.Strings.Templates is

   pragma Preelaborate;

   type Virtual_String_Template is tagged private
     with String_Literal => To_Virtual_String_Template;

   function To_Virtual_String_Template
     (Item : Wide_Wide_String) return Virtual_String_Template;

   function Format
     (Self      : Virtual_String_Template;
      Parameter : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_3 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_3 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_4 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_3 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_4 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_5 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_3 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_4 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_5 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_6 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_3 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_4 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_5 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_6 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_7 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_3 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_4 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_5 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_6 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_7 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_8 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

   function Format
     (Self        : Virtual_String_Template;
      Parameter_1 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_2 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_3 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_4 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_5 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_6 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_7 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_8 : VSS.Strings.Formatters.Abstract_Formatter'Class;
      Parameter_9 : VSS.Strings.Formatters.Abstract_Formatter'Class)
      return VSS.Strings.Virtual_String;

private

   type Virtual_String_Template is tagged record
      Template : VSS.Strings.Virtual_String;
   end record;

end VSS.Strings.Templates;