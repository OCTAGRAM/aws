------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                         Copyright (C) 2000-2004                          --
--                                ACT-Europe                                --
--                                                                          --
--  Authors: Dmitriy Anisimkov - Pascal Obry                                --
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

--  $Id$

--  Parameters name/value are put into the Table_Type.Data field (vector). The
--  name as a key and the numeric index as a value is placed into map for fast
--  retrieval of all Name/Value pairs having the same name. Each value in the
--  map is a table of numeric indexes pointing into the Data field. The
--  parameters must be accessible using their name (string index) but also
--  using an numeric index. So given a set of parameters (K1=V1, K2=V2...), one
--  must be able to ask for the value for K1 but also the name of the second
--  key or the value of the third key.
--
--  Each K/V pair is then inserted into the Data table for access by numeric
--  index. And its numeric index is placed into the map indexed by name.

with Ada.Characters.Handling;

with AI302.Containers.Generic_Array_Sort;

package body AWS.Containers.Tables is

   use Ada.Strings.Unbounded;

   procedure Get_Indexes
     (Table   : in     Table_Type;
      Name    : in     String;
      Indexes :    out Name_Index_Table;
      Found   :    out Boolean);
   pragma Inline (Get_Indexes);
   --  Returns all Name/Value indexes for the specified name.
   --  Found is set to False if Name was not found in Table and True otherwise.

   -----------
   -- Count --
   -----------

   function Count (Table : in Table_Type) return Natural is
   begin
      return Natural (Data_Table.Length (Table.Data));
   end Count;

   -----------
   -- Count --
   -----------

   function Count
     (Table : in Table_Type;
      Name  : in String)
      return Natural
   is
      Value : Name_Index_Table;
      Found : Boolean;
   begin
      Get_Indexes (Table, Name, Value, Found);

      if Found then
         return Natural (Name_Indexes.Length (Value));
      else
         return 0;
      end if;
   end Count;

   -----------
   -- Exist --
   -----------

   function Exist
     (Table : in Table_Type;
      Name  : in String)
      return Boolean is
   begin
      return Index_Table.Is_In
        (Table.Index, Normalize_Name (Name, not Table.Case_Sensitive));
   end Exist;

   ---------
   -- Get --
   ---------

   function Get
     (Table : in Table_Type;
      Name  : in String;
      N     : in Positive := 1)
      return String
   is
      Value : Name_Index_Table;
      Found : Boolean;
   begin
      Get_Indexes (Table, Name, Value, Found);

      if Found and then N <= Natural (Name_Indexes.Length (Value)) then
         return Data_Table.Element
           (Table.Data,
            Natural ((Name_Indexes.Element (Value, N)))).Value;
      else
         return "";
      end if;
   end Get;

   function Get
     (Table : in Table_Type;
      N     : in Positive)
      return Element is
   begin
      if N <= Natural (Data_Table.Length (Table.Data)) then
         return Data_Table.Element (Table.Data, N);
      else
         return Null_Element;
      end if;
   end Get;

   -----------------
   -- Get_Indexes --
   -----------------

   procedure Get_Indexes
     (Table   : in     Table_Type;
      Name    : in     String;
      Indexes :    out Name_Index_Table;
      Found   :    out Boolean)
   is
      Cursor : Index_Table.Cursor;
   begin
      Cursor := Index_Table.Find
        (Table.Index, Normalize_Name (Name, not Table.Case_Sensitive));

      if not Index_Table.Has_Element (Cursor) then
         Found := False;
      else
         Found   := True;
         Indexes := Index_Table.Element (Cursor);
      end if;
   end Get_Indexes;

   --------------
   -- Get_Name --
   --------------

   function Get_Name
     (Table : in Table_Type;
      N     : in Positive := 1)
      return String is
   begin
      if N <= Natural (Data_Table.Length (Table.Data)) then
         return Data_Table.Element (Table.Data, N).Name;
      else
         return "";
      end if;
   end Get_Name;

   ---------------
   -- Get_Names --
   ---------------

   function Get_Names
     (Table : in Table_Type;
      Sort  : in Boolean := False)
      return VString_Array
   is
      procedure Sort_Names is
        new AI302.Containers.Generic_Array_Sort
          (Positive, Unbounded_String, VString_Array);

      Result : VString_Array (1 .. Name_Count (Table));
      Cursor : Index_Table.Cursor;
      Index  : Natural := Result'First - 1;
   begin
      Cursor := Index_Table.First (Table.Index);

      while Index_Table.Has_Element (Cursor) loop
         Index := Index + 1;
         Result (Index) := To_Unbounded_String (Index_Table.Key (Cursor));
         Index_Table.Next (Cursor);
      end loop;

      if Sort then
         Sort_Names (Result);
      end if;

      return Result;
   end Get_Names;

   ---------------
   -- Get_Value --
   ---------------

   function Get_Value
     (Table : in Table_Type;
      N     : in Positive := 1)
      return String is
   begin
      if N <= Natural (Data_Table.Length (Table.Data)) then
         return Data_Table.Element (Table.Data, N).Value;
      else
         return "";
      end if;
   end Get_Value;

   ----------------
   -- Get_Values --
   ----------------

   function Get_Values
     (Table : in Table_Type;
      Name  : in String)
      return VString_Array
   is
      Value : Name_Index_Table;
      Found : Boolean;
   begin
      Get_Indexes (Table, Name, Value, Found);

      if Found then
         declare
            Last   : constant Natural
              := Natural (Name_Indexes.Length (Value));
            Result : VString_Array (1 .. Last);
         begin
            for I in 1 .. Last loop
               Result (Natural (I))
                  := To_Unbounded_String
                   (Data_Table.Element
                        (Table.Data,
                         Natural ((Name_Indexes.Element (Value, I)))).Value);
            end loop;
            return Result;
         end;

      else
         return (1 .. 0 => Null_Unbounded_String);
      end if;
   end Get_Values;

   ----------------
   -- Name_Count --
   ----------------

   function Name_Count (Table : in Table_Type) return Natural is
   begin
      return Natural (Index_Table.Length (Table.Index));
   end Name_Count;

   --------------------
   -- Normalize_Name --
   --------------------

   function Normalize_Name
     (Name     : in String;
      To_Upper : in Boolean)
      return String is
   begin
      if To_Upper then
         return Ada.Characters.Handling.To_Upper (Name);
      else
         return Name;
      end if;
   end Normalize_Name;

end AWS.Containers.Tables;
