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

with Ada.Strings.Unbounded;

private with AWS.Net;

package AWS.Jabber.Client is

   use Ada.Strings.Unbounded;

   type Account is limited private;
   type Account_Access is not null access all Account;

   Server_Error : exception;
   --  Raised by any routine below when an server or protocol error occurs. A
   --  message is attached to the exception, this correspond to the <error>
   --  XML protocol tag if present.

   type Port is new Positive;
   Default_Port : Port := 5222;

   type Authentication_Mechanism is
     (More_Secure_Mechanism, Digest_Md5_Mechanism, Plain_Mechanism);
   --  Select PLAIN or DIGEST_MD5
   --  if More_Secure_Mechanism choose DIGEST_MD5 but fallback to PLAIN if
   --  DIGEST_MD5 is not supported.

   type Jabber_ID is new String;

   function To_Jabber_ID
     (Username : String;
      Server   : String;
      Resource : String := "") return Jabber_ID;
   --  Returns a Jabber ID (username@server/resource)

   --  Jabber Hook

   type Message_Type is (M_Chat, M_Normal, M_Group_Chat, M_Headline, M_Error);

   type Message_Hook is not null access procedure
     (From         : Jabber_ID;
      Message_Type : Client.Message_Type;
      Subject      : String;
      Content      : String);

   type Presence_Hook is not null access procedure
     (From   : Jabber_ID;
      Status : String);

   procedure IO_Presence
     (From    : Jabber_ID;
      Status  : String);

   procedure IO_Message
     (From         : Jabber_ID;
      Message_Type : Client.Message_Type;
      Subject      : String;
      Content      : String);

   procedure Set_Presence_Hook
     (Account : in out Client.Account;
      Hook    : Presence_Hook);

   procedure Set_Host
     (Account : in out Client.Account;
      Host    : String);

   procedure Set_Port
     (Account : in out Client.Account;
      Port    : Client.Port);

   procedure Set_Login_Information
     (Account  : in out Client.Account;
      User     : String;
      Password : String;
      Resource : String := "");

   procedure Set_Authentication_Type
     (Account   : in out Client.Account;
      Auth_Type : Authentication_Mechanism);

   procedure Connect (Account : in out Client.Account);
   --  Connect to the jabber server

   procedure Close (Account : in out Client.Account);
   --  Close the connection

   procedure Send
     (Account      : Client.Account;
      JID          : Jabber_ID;
      Content      : String;
      Subject      : String := "";
      Message_Type : Client.Message_Type := M_Normal);
   --  Send a message to user JID (Jabber ID) via the specified Server. The
   --  message is composed of Subject and a body (Content).

private
   --  Jabber Client and Server open a stream and both communicate with each
   --  others via this channel. All messages exchanged are XML encoded. Both
   --  streams (client -> server and server -> client) have a common
   --  structure:
   --
   --  <?xml version=""1.0"" encoding=""UTF-8"" ?>"
   --  <stream:stream>
   --     <message> ... </message>
   --     <presence> ... </presence>
   --  </stream:stream>
   --
   --  As both streams are sent asynchronously, we use a Task to read the
   --  incoming stream. This task is responsible to accept incoming XML
   --  message, to parse them, create a Message object and run the Presence and
   --  Message hooks.

   type Jabber_Hooks is limited record
      Presence : Presence_Hook := IO_Presence'Access;
      Message  : Message_Hook  := IO_Message'Access;
   end record;

   ---------------------
   -- Incoming_Stream --
   ---------------------

   --  Read incoming XML messages, parse them and add them to the
   --  Mailbox. This task will terminate with the connection socket will be
   --  closed by the client.

   task type Incoming_Stream (Account : Account_Access);
   type Incoming_Stream_Access is access Incoming_Stream;

   type Connection_State is
     (Initialize_Connection, Start_Authentication, Connected);

   type User_Data is limited record
      Name     : Unbounded_String;
      Password : Unbounded_String;
      Resource : Unbounded_String;
      JID      : Unbounded_String;
   end record;

   type Account is limited record
      Self       : Account_Access := Account'Unchecked_Access;
      User       : User_Data;
      Host       : Unbounded_String;
      Port       : Client.Port := Default_Port;
      Stream     : Incoming_Stream_Access;
      Sock       : Net.Socket_Access;
      Is_Running : Boolean := False;
      SID        : Unbounded_String;
      Auth_Type  : Authentication_Mechanism := More_Secure_Mechanism;
      Hooks      : Jabber_Hooks;
   end record;

end AWS.Jabber.Client;
