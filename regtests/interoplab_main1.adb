------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                         Copyright (C) 2003-2004                          --
--                                ACT-Europe                                --
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

--  ~ MAIN [SOAP]

with Ada.Calendar;
with Ada.Integer_Text_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AWS.MIME;
with AWS.Response;
with AWS.Server;
with AWS.Status;
with AWS.Translator;
with SOAP.Message.XML;
with SOAP.Message.Payload;

with Tinteroplab.Client;
with Tinteroplab.Server;
with Tinteroplab.Types;

procedure Interoplab_Main1 is

   use Ada;
   use AWS;

   use Tinteroplab.Types;
   use Ada.Strings.Unbounded;

   H_Server : AWS.Server.HTTP;

   function "+"
     (Str : in String)
      return Unbounded_String
      renames To_Unbounded_String;

   package LFIO is new Text_IO.Float_IO (Long_Float);

   ------------
   -- Output --
   ------------

   procedure Output (S : in SOAPStruct_Type) is
   begin
      Integer_Text_IO.Put (S.varInt); Text_IO.New_Line;
      LFIO.Put (S.VarFloat, Exp => 0, Aft => 2); Text_IO.New_Line;
      Text_IO.Put_Line (To_String (S.varString));
   end Output;

   ---------------------
   -- T_echoString_CB --
   ---------------------

   function T_echoString_CB (inputString : in String) return String is
   begin
      return inputString;
   end T_echoString_CB;

   function echoString_CB is
      new Tinteroplab.Server.echoString_CB (T_echoString_CB);

   ------------------
   -- T_echoString --
   ------------------

   procedure T_echoString is
      Res : constant String := TinteropLab.Client.echoString
        ("This is the real value for the string!");
   begin
      Text_IO.Put_Line ("Echo String");

      Text_IO.Put_Line (Res);
      Text_IO.New_Line;
   end T_echoString;

   --------------------------
   -- T_echoStringArray_CB --
   --------------------------

   function T_echoStringArray_CB
      (inputStringArray : in ArrayOfstring_Type)
       return echoStringArray_Result is
   begin
      return inputStringArray;
   end T_echoStringArray_CB;

   function echoStringArray_CB is
      new Tinteroplab.Server.echoStringArray_CB (T_echoStringArray_CB);

   -----------------------
   -- T_echoStringArray --
   -----------------------

   procedure T_echoStringArray is
      Arr : constant ArrayOfstring_Type := (+"first", +"second", +"third");

      Res : constant ArrayOfstring_Type
        := TinteropLab.Client.echoStringArray (Arr);
   begin
      Text_IO.Put_Line ("Echo ArrayOfstring");
      for K in Res'Range loop
         Text_IO.Put_Line (Integer'Image (K) & " = " & To_String (Res (K)));
      end loop;
      Text_IO.New_Line;
   end T_echoStringArray;

   ----------------------
   -- T_echoBoolean_CB --
   ----------------------

   function T_echoBoolean_CB
     (inputBoolean : in Boolean)
      return Boolean is
   begin
      return inputBoolean;
   end T_echoBoolean_CB;

   function echoBoolean_CB is
      new Tinteroplab.Server.echoBoolean_CB (T_echoBoolean_CB);

   -------------------
   -- T_echoBoolean --
   -------------------

   procedure T_echoBoolean is
      Res : Boolean;
   begin
      Text_IO.Put_Line ("Echo Boolean");

      Res := TinteropLab.Client.echoBoolean (True);
      Text_IO.Put_Line (Boolean'Image (Res));

      Res := TinteropLab.Client.echoBoolean (False);
      Text_IO.Put_Line (Boolean'Image (Res));
      Text_IO.New_Line;
   end T_echoBoolean;

   ---------------------
   -- T_echoBase64_CB --
   ---------------------

   function T_echoBase64_CB
     (inputBase64 : in String)
      return String is
   begin
      return inputBase64;
   end T_echoBase64_CB;

   function echoBase64_CB is
      new Tinteroplab.Server.echoBase64_CB (T_echoBase64_CB);

   ------------------
   -- T_echoBase64 --
   ------------------

   procedure T_echoBase64 is
      V   : constant String
        := AWS.Translator.Base64_Encode ("AWS SOAP WSDL implementation");
      Res : constant String := TinteropLab.Client.echoBase64 (V);
   begin
      Text_IO.Put_Line ("Echo Base64");

      Text_IO.Put_Line (V);
      Text_IO.Put_Line (Res);
      Text_IO.New_Line;
   end T_echoBase64;

   ----------------------
   -- T_echoInteger_CB --
   ----------------------

   function T_echoInteger_CB
      (inputInteger : in Integer)
       return Integer is
   begin
      return inputInteger;
   end T_echoInteger_CB;

   function echoInteger_CB is
      new Tinteroplab.Server.echoInteger_CB (T_echoInteger_CB);

   -------------------
   -- T_echoInteger --
   -------------------

   procedure T_echoInteger is
   begin
      Text_IO.Put_Line ("Echo Integer");
      Integer_Text_IO.Put (TinteropLab.Client.echoInteger (12));
      Text_IO.New_Line;
      Integer_Text_IO.Put (TinteropLab.Client.echoInteger (9876543));
      Text_IO.New_Line;
      Text_IO.New_Line;
   end T_echoInteger;

   ---------------------------
   -- T_echoIntegerArray_CB --
   ---------------------------

   function T_echoIntegerArray_CB
      (inputIntegerArray : in ArrayOfint_Type)
       return echoIntegerArray_Result is
   begin
      return inputIntegerArray;
   end T_echoIntegerArray_CB;

   function echoIntegerArray_CB is
      new Tinteroplab.Server.echoIntegerArray_CB (T_echoIntegerArray_CB);

   ------------------------
   -- T_echoIntegerArray --
   ------------------------

   procedure T_echoIntegerArray is
      Arr : constant ArrayOfint_Type := (34, 67, 98, 54, 78, 65, 1);

      Res : constant ArrayOfint_Type
        := TinteropLab.Client.echoIntegerArray (Arr);
   begin
      Text_IO.Put_Line ("Echo ArrayOfint");
      for K in Res'Range loop
         Text_IO.Put (Integer'Image (K) & " = ");
         Integer_Text_IO.Put (Res (K));
         Text_IO.New_Line;
      end loop;
      Text_IO.New_Line;
   end T_echoIntegerArray;

   --------------------
   -- T_echoFloat_CB --
   --------------------

   function T_echoFloat_CB
      (inputFloat : in Long_Float)
       return Long_Float is
   begin
      return inputFloat;
   end T_echoFloat_CB;

   function echoFloat_CB is
      new Tinteroplab.Server.echoFloat_CB (T_echoFloat_CB);

   -----------------
   -- T_echoFloat --
   -----------------

   procedure T_echoFloat is
   begin
      Text_IO.Put_Line ("Echo Float");
      LFIO.Put (TinteropLab.Client.echoFloat (2.345), Aft => 5, Exp => 0);
      Text_IO.New_Line;
      LFIO.Put (TinteropLab.Client.echoFloat (456.8765), Aft => 5, Exp => 0);
      Text_IO.New_Line;
      Text_IO.New_Line;
   end T_echoFloat;

   ---------------------
   -- T_echoStruct_CB --
   ---------------------

   function T_echoStruct_CB
      (inputStruct : in SOAPStruct_Type)
       return echoStruct_Result is
   begin
      return inputStruct;
   end T_echoStruct_CB;

   function echoStruct_CB is
      new Tinteroplab.Server.echoStruct_CB (T_echoStruct_CB);

   ------------------
   -- T_echoStruct --
   ------------------

   procedure T_echoStruct is
      Struct : constant SOAPStruct_Type
        := (6, 6.6, +"666");

      pragma Warnings (Off);
      --  Suppress a wrong warnings issued by GNAT, this is fixed in
      --  GNAT 3.17
      Res : constant echoStruct_Result
        := TinteropLab.Client.echoStruct (Struct);
   begin
      Text_IO.Put_Line ("Echo Struct");
      Output (Res);
      Text_IO.New_Line;
   end T_echoStruct;

   -------------------
   -- T_echoDate_CB --
   -------------------

   function T_echoDate_CB
      (inputDate : in Ada.Calendar.Time)
       return Ada.Calendar.Time is
   begin
      return inputDate;
   end T_echoDate_CB;

   function echoDate_CB is
      new Tinteroplab.Server.echoDate_CB (T_echoDate_CB);

   ----------------
   -- T_echoDate --
   ----------------

   procedure T_echoDate is
      use type Ada.Calendar.Time;

      T   : constant Ada.Calendar.Time
        := Ada.Calendar.Time_Of (2003, 3, 12, 39482.0);
      Res : Ada.Calendar.Time;
   begin
      Text_IO.Put_Line ("Echo Date");
      Res := TinteropLab.Client.echoDate (T);

      if Res = T then
         Text_IO.Put_Line ("ok");
      else
         Text_IO.Put_Line ("nok");
      end if;
      Text_IO.New_Line;
   end T_echoDate;

   -------------------------
   -- T_echoFloatArray_CB --
   -------------------------

   function T_echoFloatArray_CB
      (inputFloatArray : in ArrayOffloat_Type)
       return EchoFloatArray_Result is
   begin
      return inputFloatArray;
   end T_echoFloatArray_CB;

   function echoFloatArray_CB is
      new Tinteroplab.Server.echoFloatArray_CB (T_echoFloatArray_CB);

   ----------------------
   -- T_echoFloatArray --
   ----------------------

   procedure T_echoFloatArray is
      Arr : constant ArrayOfFloat_Type
        := (34.1, 67.2, 98.3, 54.4, 78.5, 65.6, 1.7);

      Res : constant ArrayOfFloat_Type
        := TinteropLab.Client.echoFloatArray (Arr);
   begin
      Text_IO.Put_Line ("Echo ArrayOfFloat");

      for K in Res'Range loop
         Text_IO.Put (Integer'Image (K) & " = ");
         LFIO.Put (Res (K), Aft => 2, Exp => 0);
         Text_IO.New_Line;
      end loop;
      Text_IO.New_Line;
   end T_echoFloatArray;

   ---------------------
   -- echoStructArray --
   ---------------------

   function T_echoStructArray_CB
      (inputStructArray : in ArrayOfSOAPStruct_Type)
       return echoStructArray_Result is
   begin
      return inputStructArray;
   end T_echoStructArray_CB;

   function echoStructArray_CB is
      new Tinteroplab.Server.echoStructArray_CB (T_echoStructArray_CB);

   -----------------------
   -- T_echoStructArray --
   -----------------------

   procedure T_echoStructArray is
      A_Struct : constant ArrayOfSOAPStruct_Type
        := ((1, 1.1, +"one"), (2, 2.2, +"two"), (3, 3.3, +"three"));

      Res : constant ArrayOfSOAPStruct_Type
        := TinteropLab.Client.echoStructArray (A_Struct);
   begin
      Text_IO.Put_Line ("Echo ArrayOfStruct");

      for K in Res'Range loop
         Output (Res (K));
      end loop;

      Text_IO.New_Line;
   end T_echoStructArray;

   -------------------
   -- T_echoVoid_CB --
   -------------------

   procedure T_echoVoid_CB is
   begin
      null;
   end T_echoVoid_CB;

   function echoVoid_CB is
      new Tinteroplab.Server.echoVoid_CB (T_echoVoid_CB);

   ----------------
   -- T_echoVoid --
   ----------------

   procedure T_echoVoid is
   begin
      Text_IO.Put_Line ("Echo Void");
      Tinteroplab.Client.echoVoid;
      Text_IO.New_Line;
   end T_echoVoid;

   --------
   -- CB --
   --------

   function CB (Request : in Status.Data) return Response.Data is
      SOAPAction : constant String := Status.SOAPAction (Request);
      Payload    : constant SOAP.Message.Payload.Object
        := SOAP.Message.XML.Load_Payload (AWS.Status.Payload (Request));
   begin
      if SOAPAction = "http://t_soapinterop.org/#echoString" then
         return echoString_CB (SOAPAction, Payload, Request);

      elsif SOAPAction = "http://t_soapinterop.org/#echoVoid" then
         return echoVoid_CB (SOAPAction, Payload, Request);

      elsif SOAPAction = "http://t_soapinterop.org/" then
         declare
            Proc : constant String
              := SOAP.Message.Payload.Procedure_Name (Payload);
         begin
            if Proc = "echoString" then
               return echoString_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoStringArray" then
               return echoStringArray_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoBoolean" then
               return echoBoolean_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoBase64" then
               return echoBase64_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoInteger" then
               return echoInteger_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoIntegerArray" then
               return echoIntegerArray_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoFloat" then
               return echoFloat_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoStruct" then
               return echoStruct_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoDate" then
               return echoDate_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoFloatArray" then
               return echoFloatArray_CB (SOAPAction, Payload, Request);

            elsif Proc = "echoStructArray" then
               return echoStructArray_CB (SOAPAction, Payload, Request);

            else
               return Response.Build
                 (MIME.Text_HTML, "Not a SOAP request, Proc=" & Proc);
            end if;
         end;

      else
         return Response.Build
           (MIME.Text_HTML, "Not a SOAP request, SOAPAction=" & SOAPAction);
      end if;
   end CB;

begin
   AWS.Server.Start
     (H_Server, "WSDL interopLab Server",
      CB'Unrestricted_Access,
      Port => Tinteroplab.Server.Port);

   T_echoVoid;
   T_echoString;
   T_echoStringArray;
   T_echoBoolean;
   T_echoBase64;
   T_echoInteger;
   T_echoIntegerArray;
   T_echoFloat;
   T_echoStruct;
   T_echoDate;
   T_echoFloatArray;
   T_echoStructArray;

   AWS.Server.Shutdown (H_Server);
end Interoplab_Main1;
