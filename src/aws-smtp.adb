------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                   S M T P - Simple Mail Transfer Protocol                --
--                                                                          --
--                         Copyright (C) 2000-2004                          --
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

with Ada.Strings.Fixed;

package body AWS.SMTP is

   use Ada;

   C_211 : aliased constant String := "System status";
   C_214 : aliased constant String := "Help message";
   C_220 : aliased constant String := "AdaSC Service ready";
   C_221 : aliased constant String := "Service closing transmission channel";
   C_250 : aliased constant String := "Requested mail action okay, completed";
   C_251 : aliased constant String := "User not local; will forward";
   C_354 : aliased constant String :=
     "Start mail input; end with <CRLF>.<CRLF>";
   C_421 : aliased constant String :=
     "Service not available, closing transmission channel";
   C_450 : aliased constant String :=
     "Requested mail action not taken: mailbox unavailable";
   C_451 : aliased constant String :=
     "Requested action aborted: local error in processing";
   C_452 : aliased constant String :=
     "Requested action not taken: insufficient system storage";
   C_500 : aliased constant String := "Syntax error, command unrecognized";
   C_501 : aliased constant String :=
     "Syntax error in parameters or arguments";
   C_502 : aliased constant String := "Command not implemented";
   C_503 : aliased constant String := "Bad sequence of commands";
   C_504 : aliased constant String := "Command parameter not implemented";
   C_550 : aliased constant String :=
     "Requested action not taken: mailbox unavailable";
   C_551 : aliased constant String :=
     "User not local; please try <forward-path>";
   C_552 : aliased constant String :=
     "Requested mail action aborted: exceeded storage allocation";
   C_553 : aliased constant String :=
     "Requested action not taken: mailbox name not allowed";
   C_554 : aliased constant String := "Transaction failed";

   type Code_Name is access constant String;

   type Reply_Code_Data is record
      Code : Reply_Code;
      Name : Code_Name;
   end record;

   Code_Table : constant array (1 .. 21) of Reply_Code_Data :=
     ((211, C_211'Access), (214, C_214'Access), (220, C_220'Access),
      (221, C_221'Access), (250, C_250'Access), (251, C_251'Access),
      (354, C_354'Access), (421, C_421'Access), (450, C_450'Access),
      (451, C_451'Access), (452, C_452'Access), (500, C_500'Access),
      (501, C_501'Access), (502, C_502'Access), (503, C_503'Access),
      (504, C_504'Access), (550, C_550'Access), (551, C_551'Access),
      (552, C_552'Access), (553, C_553'Access), (554, C_554'Access));

   -----------
   -- Clear --
   -----------

   procedure Clear (Status : in out SMTP.Status) is
   begin
      Status := (Null_Unbounded_String, Requested_Action_Ok);
   end Clear;

   ------------
   -- E_Mail --
   ------------

   function E_Mail (Name : in String; Address : in String)
     return E_Mail_Data is
   begin
      return (To_Unbounded_String (Name), To_Unbounded_String (Address));
   end E_Mail;

   -----------
   -- Image --
   -----------

   function Image (R : in Reply_Code) return String is
      RI : constant String := Reply_Code'Image (R);
   begin
      for K in Code_Table'Range loop
         if Code_Table (K).Code = R then
            return RI (RI'First + 1 .. RI'Last);
         end if;
      end loop;

      raise Reply_Code_Error;
   end Image;

   function Image
     (E_Mail : in E_Mail_Data;
      Mode   : in Address_Mode := Full) return String is
   begin
      case Mode is
         when Full =>
            return To_String (E_Mail.Name)
              & " <" & To_String (E_Mail.Address) & '>';
         when Name =>
            return To_String (E_Mail.Name);
         when Address =>
            return To_String (E_Mail.Address);
      end case;
   end Image;

   -----------
   -- Is_Ok --
   -----------

   function Is_Ok (Status : in SMTP.Status) return Boolean is
   begin
      return Status.Value = Null_Unbounded_String;
   end Is_Ok;

   -------------
   -- Message --
   -------------

   function Message (R : in Reply_Code) return String is
   begin
      return Image (R) & ' ' & Name (R);
   end Message;

   ----------
   -- Name --
   ----------

   function Name (R : in Reply_Code) return String is
   begin
      for K in Code_Table'Range loop
         if Code_Table (K).Code = R then
            return Code_Table (K).Name.all;
         end if;
      end loop;

      raise Reply_Code_Error;
   end Name;

   -----------
   -- Parse --
   -----------

   function Parse (E_Mail : in String) return E_Mail_Data is
      use Strings.Fixed;

      I1, I2 : Natural;
   begin
      I1 := Index (E_Mail, "<");
      I2 := Index (E_Mail, ">");

      if I1 = 0 or else I2 = 0 or else I1 > I2 then

         I1 := Index (E_Mail, "(");
         I2 := Index (E_Mail, ")");

         if I1 = 0 or else I2 = 0 or else I1 > I2 then
            raise Constraint_Error;
         else
            --  Syntax: e-mail (Name)
            return SMTP.E_Mail
              (Address => Trim (E_Mail (E_Mail'First .. I1 - 1), Strings.Both),
               Name    => Trim (E_Mail (I1 + 1 .. I2 - 1), Strings.Both));
         end if;

      else
         --  Syntax: Name <e-mail>
         return SMTP.E_Mail
           (Name    => Trim (E_Mail (E_Mail'First .. I1 - 1), Strings.Both),
            Address => Trim (E_Mail (I1 + 1 .. I2 - 1), Strings.Both));
      end if;
   end Parse;

   -----------------
   -- Status_Code --
   -----------------

   function Status_Code (Status : in SMTP.Status) return Reply_Code is
   begin
      return Status.Code;
   end Status_Code;

   --------------------
   -- Status_Message --
   --------------------

   function Status_Message (Status : in SMTP.Status) return String is
   begin
      return To_String (Status.Value);
   end Status_Message;

end AWS.SMTP;
