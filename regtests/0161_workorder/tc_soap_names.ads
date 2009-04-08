------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                     Copyright (C) 2008-2009, AdaCore                     --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

with SOAP.Types; use SOAP.Types;

package Tc_Soap_Names is

   Soap_Ws        : constant String := "Workstation";
   Soap_Updated   : constant String := "Updated";
   Soap_Wo        : constant String := "Workorder";
   Soap_WoId      : constant String := "Woid";
   Soap_State     : constant String := "State";
   Soap_Package   : constant String := "Package";
   Soap_Recipe    : constant String := "Recipe";
   Soap_Orderline : constant String := "Orderline";
   Soap_TwelveNc  : constant String := "Twelvenc";
   Soap_Type      : constant String := "Type";
   Soap_Priority  : constant String := "Priority";
   Soap_Label     : constant String := "Label";
   Soap_Quantity  : constant String := "Quantity";
   Soap_Packing   : constant String := "Packing";
   Soap_Marking   : constant String := "Marking";
   Soap_Orient    : constant String := "Orientation";
   Soap_Produced  : constant String := "Produced";

   function Soap_Image
     (Obj    : SOAP.Types.Object'Class;
      Indent : Integer := 0) return String;

end Tc_Soap_Names;
