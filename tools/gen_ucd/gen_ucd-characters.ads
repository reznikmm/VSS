------------------------------------------------------------------------------
--                        M A G I C   R U N T I M E                         --
--                                                                          --
--                       Copyright (C) 2021, AdaCore                        --
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

with Gen_UCD.Properties;

package Gen_UCD.Characters is

   type Character_Information is private;

   procedure Initialize_Character_Database;

   procedure Set
     (Character : Code_Point;
      Property  : not null Properties.Property_Access;
      Value     : not null Properties.Property_Value_Access);

   function Get
     (Character : Code_Point;
      Property  : not null Properties.Property_Access)
        return not null Properties.Property_Value_Access;

private

   type Character_Record;

   type Character_Information is access all Character_Record;

end Gen_UCD.Characters;