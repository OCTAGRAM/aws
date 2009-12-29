------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                     Copyright (C) 2005-2009, AdaCore                     --
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

with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.MD5;

with AWS.Attachments;
with AWS.Digest;
with AWS.Dispatchers;
with AWS.Headers.Set;
with AWS.Headers.Values;
with AWS.Hotplug;
with AWS.Log;
with AWS.Messages;
with AWS.MIME;
with AWS.Net;
with AWS.Net.Buffered;
with AWS.Parameters;
with AWS.Response.Set;
with AWS.Session;
with AWS.Server.Get_Status;
with AWS.Status.Set;
with AWS.Templates;
with AWS.Translator;
with AWS.Utils;
with AWS.URL;

package body AWS.Server.HTTP_Utils is

   use Ada;
   use Ada.Strings;
   use Ada.Strings.Unbounded;
   use Ada.Streams;
   use AWS.Templates;

   protected File_Upload_UID is
      procedure Get (ID : out Natural);
      --  returns a UID for file upload. This is to ensure that files
      --  coming from clients will always have different name.
   private
      UID : Natural := 0;
   end File_Upload_UID;

   ----------------------
   -- Answer_To_Client --
   ----------------------

   procedure Answer_To_Client
     (HTTP_Server  : in out AWS.Server.HTTP;
      Line_Index   : Positive;
      C_Stat       : in out AWS.Status.Data;
      Socket_Taken : in out Boolean;
      Will_Close   : in out Boolean)
   is
      use type Messages.Status_Code;

      Admin_URI : constant String := CNF.Admin_URI (HTTP_Server.Properties);
      Answer    : Response.Data;

      procedure Build_Answer;
      --  Build the Answer that should be sent to the client's browser

      procedure Create_Session;
      --  Create a session if needed

      function Status_Page (URI : String) return Response.Data;
      --  Handle status page
      --
      ------------------
      -- Build_Answer --
      ------------------

      procedure Build_Answer is
         URL : constant AWS.URL.Object := AWS.Status.URI (C_Stat);
         URI : constant String         := AWS.URL.Abs_Path (URL);
      begin
         --  Check if the status page, status page logo or status page images
         --  are requested. These are AWS internal data that should not be
         --  handled by AWS users.

         --  AWS Internal status page handling

         if Admin_URI'Length > 0
           and then
             URI'Length >= Admin_URI'Length
             and then
               URI (URI'First .. URI'First + Admin_URI'Length - 1) = Admin_URI
         then
            Answer := Status_Page (URI);

            --  Check if the URL is trying to reference resource above Web root
            --  directory.

         elsif CNF.Check_URL_Validity (HTTP_Server.Properties)
           and then not AWS.URL.Is_Valid (URL)
         then
            --  403 status code "Forbidden"

            Answer := Response.Build
              (Status_Code   => Messages.S403,
               Content_Type  => "text/plain",
               Message_Body  => "Request " & URI & ASCII.LF
               & " trying to reach resource above the Web root directory.");

         else
            --  Otherwise, check if a session needs to be created

            Create_Session;

            --  and get answer from client callback

            declare
               use type Dispatchers.Handler_Class_Access;
               Found : Boolean;
            begin
               --  Check the hotplug filters

               Hotplug.Apply (HTTP_Server.Filters, C_Stat, Found, Answer);

               --  If no one applied, run the user callback

               if not Found then
                  if HTTP_Server.New_Dispatcher /= null then
                     HTTP_Server.Dispatcher_Sem.Write;
                     Dispatchers.Free (HTTP_Server.Dispatcher);
                     HTTP_Server.Dispatcher := HTTP_Server.New_Dispatcher;
                     HTTP_Server.New_Dispatcher := null;
                     HTTP_Server.Dispatcher_Sem.Release_Write;
                  end if;

                  HTTP_Server.Dispatcher_Sem.Read;

                  --  Be sure to always release the read semaphore

                  begin
                     Answer := Dispatchers.Dispatch
                       (HTTP_Server.Dispatcher.all, C_Stat);

                     HTTP_Server.Dispatcher_Sem.Release_Read;
                  exception
                     when others =>
                        HTTP_Server.Dispatcher_Sem.Release_Read;
                        raise;
                  end;
               end if;
            end;

            AWS.Status.Set.Delete_Idle_Session (C_Stat);
         end if;
      end Build_Answer;

      --------------------
      -- Create_Session --
      --------------------

      procedure Create_Session is
         use type Session.Id;
      begin
         if CNF.Session (HTTP_Server.Properties)
           and then (not Status.Has_Session (C_Stat)
                     or else not Session.Exist (Status.Session (C_Stat)))
         then
            --  Generate the session ID
            Status.Set.Session (C_Stat);
         end if;
      end Create_Session;

      -----------------
      -- Status_Page --
      -----------------

      function Status_Page (URI : String) return Response.Data is
         use type AWS.Status.Authorization_Type;
         Answer   : Response.Data;
         Username : constant String :=
                      AWS.Status.Authorization_Name (C_Stat);
         Password : constant String :=
                      AWS.Status.Authorization_Password (C_Stat);
         Method   : constant AWS.Status.Authorization_Type :=
                      AWS.Status.Authorization_Mode (C_Stat);

         procedure Answer_File (File_Name : String);
         --  Assign File to Answer response data

         -----------------
         -- Answer_File --
         -----------------

         procedure Answer_File (File_Name : String) is
         begin
            Answer := Response.File
              (Content_Type => MIME.Content_Type (File_Name),
               Filename     => File_Name);
         end Answer_File;

      begin
         --  First check for authentification

         if Method = AWS.Status.Digest then
            if AWS.Status.Authorization_Response (C_Stat)
               = GNAT.MD5.Digest
                   (CNF.Admin_Password (HTTP_Server.Properties)
                    & AWS.Status.Authorization_Tail (C_Stat))
            then
               if not AWS.Digest.Check_Nonce
                        (Status.Authorization_Nonce (C_Stat))
               then
                  return AWS.Response.Authenticate
                           (CNF.Admin_Realm (HTTP_Server.Properties),
                            AWS.Response.Digest,
                            Stale => True);
               end if;

            else
               return AWS.Response.Authenticate
                        (CNF.Admin_Realm (HTTP_Server.Properties),
                         AWS.Response.Digest);
            end if;

         elsif (Method = AWS.Status.Basic
                and then CNF.Admin_Password (HTTP_Server.Properties)
                         /= GNAT.MD5.Digest
                              (Username
                               & ':' & CNF.Admin_Realm (HTTP_Server.Properties)
                               & ':' & Password))
           or else Method = AWS.Status.None or else Password = ""
         then
            return Response.Authenticate
                     (CNF.Admin_Realm (HTTP_Server.Properties), Response.Any);
         end if;

         if URI = Admin_URI then

            --  Status page
            begin
               Answer := Response.Build
                 (Content_Type => MIME.Text_HTML,
                  Message_Body => Get_Status (HTTP_Server));
            exception
               when Templates.Template_Error =>
                  Answer := Response.Build
                    (Content_Type => MIME.Text_HTML,
                     Message_Body =>
                     "Status template error. Please check "
                     & "that '" & CNF.Status_Page (HTTP_Server.Properties)
                     & "' file is valid.");
            end;

         elsif URI = Admin_URI & "-logo" then
            --  Status page logo
            Answer_File (CNF.Logo_Image (HTTP_Server.Properties));

         elsif URI = Admin_URI & "-uparr" then
            --  Status page hotplug up-arrow
            Answer_File (CNF.Up_Image (HTTP_Server.Properties));

         elsif URI = Admin_URI & "-downarr" then
            --  Status page hotplug down-arrow
            Answer_File (CNF.Down_Image (HTTP_Server.Properties));

         elsif URI = Admin_URI & "-HPup" then
            --  Status page hotplug up message
            Hotplug.Move_Up
              (HTTP_Server.Filters,
               Positive'Value (Status.Parameter (C_Stat, "N")));
            Answer := Response.URL (Admin_URI);

         elsif URI = Admin_URI & "-HPdown" then
            --  Status page hotplug down message
            Hotplug.Move_Down
              (HTTP_Server.Filters,
               Positive'Value (Status.Parameter (C_Stat, "N")));
            Answer := Response.URL (Admin_URI);

         else
            Answer := Response.Build
              (Content_Type => MIME.Text_HTML,
               Message_Body =>
                 "Invalid use of reserved status URI prefix: " & Admin_URI);
         end if;

         return Answer;
      end Status_Page;

   begin
      Build_Answer;

      if HTTP_Server.Slots.Phase (Line_Index) = Client_Data then
         --  User callback did not read clients message body. If client do not
         --  support 100 (Continue) response, we have to close
         --  socket to discard pending client data.

         if not Will_Close then
            Will_Close := Status.Expect (C_Stat) /= Messages.S100_Continue;
         end if;

         if Response.Status_Code (Answer) < Messages.S300 then
            Log.Write
              (HTTP_Server.Error_Log,
               C_Stat,
               "User does not upload server data but return status "
               & Messages.Image (Response.Status_Code (Answer)));
         end if;
      end if;

      Send (Answer, HTTP_Server, Line_Index, C_Stat, Socket_Taken, Will_Close);
   end Answer_To_Client;

   ---------------------
   -- File_Upload_UID --
   ---------------------

   protected body File_Upload_UID is

      ---------
      -- Get --
      ---------

      procedure Get (ID : out Natural) is
      begin
         ID  := UID;
         UID := UID + 1;
      end Get;

   end File_Upload_UID;

   ----------------------
   -- Get_Message_Data --
   ----------------------

   procedure Get_Message_Data
     (HTTP_Server : in out AWS.Server.HTTP;
      Line_Index  : Positive;
      C_Stat      : in out AWS.Status.Data;
      Expect_100  : Boolean)
   is
      use type Status.Request_Method;

      type Message_Mode is
        (Root_Attachment,   -- Read the root attachment
         Attachment,        -- Read an attachment
         File_Upload);      -- Read a file upload

      procedure Get_File_Data
        (Server_Filename : String;
         Filename        : String;
         Start_Boundary  : String;
         Mode            : Message_Mode;
         Headers         : AWS.Headers.List;
         End_Found       : out Boolean);
      --  Read file data from the stream, set End_Found if the end-boundary
      --  signature has been read. Server_Filename is the filename to be used
      --  for on-disk content (Attachment and File_Upload mode).

      procedure File_Upload
        (Start_Boundary, End_Boundary : String;
         Parse_Boundary               : Boolean);
      --  Handle file upload data coming from the client browser

      procedure Store_Attachments
        (Start_Boundary, End_Boundary : String;
         Parse_Boundary               : Boolean;
         Root_Part_CID                : String);
      --  Store attachments coming from the client browser

      Status_Multipart_Boundary : Unbounded_String;
      Status_Root_Part_CID      : Unbounded_String;
      Status_Content_Type       : Unbounded_String;

      Sock : constant Net.Socket_Type'Class := Status.Socket (C_Stat);

      Attachments : AWS.Attachments.List;

      -----------------
      -- File_Upload --
      -----------------

      procedure File_Upload
        (Start_Boundary, End_Boundary : String;
         Parse_Boundary               : Boolean)
      is
         Name            : Unbounded_String;
         Filename        : Unbounded_String;
         Server_Filename : Unbounded_String;
         Is_File_Upload  : Boolean;
         Headers         : AWS.Headers.List;

         End_Found       : Boolean := False;
         --  Set to true when the end-boundary has been found

         function Target_Filename (Filename : String) return String;
         --  Returns the full path name for the file as stored on the
         --  server side.

         ---------------------
         -- Target_Filename --
         ---------------------

         function Target_Filename (Filename : String) return String is
            Upload_Path : constant String :=
                            CNF.Upload_Directory (HTTP_Server.Properties);
            UID         : Natural;
         begin
            File_Upload_UID.Get (UID);

            return Upload_Path & Utils.Image (UID) & '.' & Filename;
         end Target_Filename;

      begin -- File_Upload
         --  Reach the boundary

         if Parse_Boundary then
            loop
               declare
                  Data : constant String := Net.Buffered.Get_Line (Sock);
               begin
                  exit when Data = Start_Boundary;

                  if Data = End_Boundary then
                     --  This is the end of the multipart data
                     return;
                  end if;
               end;
            end loop;
         end if;

         --  Read header

         AWS.Headers.Set.Read (Sock, Headers);

         if AWS.Headers.Get_Values
           (Headers, Messages.Content_Type_Token) = MIME.Application_Form_Data
         then
            --  This chunk is the form parameter
            Status.Set.Read_Body
              (Sock, C_Stat, Boundary => Start_Boundary);

            --  Skip CRLF after boundary

            declare
               Data : constant String := Net.Buffered.Get_Line (Sock);
               pragma Unreferenced (Data);
            begin
               null;
            end;

            Status.Set.Parameters_From_Body (C_Stat);

            File_Upload (Start_Boundary, End_Boundary, False);

         else
            --  Read file upload parameters

            declare
               Data       : constant String :=
                              AWS.Headers.Get_Values
                                (Headers, Messages.Content_Disposition_Token);
               L_Name     : constant String :=
                              AWS.Headers.Values.Search (Data, "name");
               L_Filename : constant String :=
                              AWS.Headers.Values.Search (Data, "filename");
               --  Get the simple name as we do not want to expose the client
               --  full pathname to the user's callback. Microsoft Internet
               --  Explorer sends the full pathname, Firefox only send the
               --  simple name.
            begin
               Is_File_Upload := (L_Filename /= "");

               Name := To_Unbounded_String (L_Name);

               if Is_File_Upload then
                  Filename := To_Unbounded_String
                    (Directories.Simple_Name (L_Filename));
               end if;
            end;

            --  Read file/field data

            if Is_File_Upload then
               --  This part of the multipart message contains file data

               if CNF.Upload_Directory (HTTP_Server.Properties) = "" then
                  raise Constraint_Error
                    with "File upload not supported by server "
                      & CNF.Server_Name (HTTP_Server.Properties);
               end if;

               --  Set Server_Filename, the name of the file in the local file
               --  sytstem.

               Server_Filename := To_Unbounded_String
                 (Target_Filename (To_String (Filename)));

               if To_String (Filename) /= "" then
                  --  First value is the unique name on the server side

                  Status.Set.Add_Parameter
                    (C_Stat, To_String (Name), To_String (Server_Filename));
                  --  Status.Set.Add_Parameter does not decode values

                  --  Second value is the original name as found on the client
                  --  side.

                  Status.Set.Add_Parameter
                    (C_Stat, To_String (Name), To_String (Filename));
                  --  Status.Set.Add_Parameter does not decode values

                  --  Read file data, set End_Found if the end-boundary
                  --  signature has been read.

                  Get_File_Data
                    (To_String (Server_Filename),
                     To_String (Filename),
                     Start_Boundary,
                     File_Upload,
                     Headers,
                     End_Found);

                  --  Create an attachment entry, this will ensure that the
                  --  physical file will be removed. It will also be possible
                  --  to work with the attachment instead of the parameters set
                  --  above.
                  AWS.Attachments.Add
                    (Attachments,
                     Filename   => To_String (Server_Filename),
                     Name       => To_String (Filename),
                     Content_Id => To_String (Name),
                     Headers    => Headers);
                  Status.Set.Attachments (C_Stat, Attachments);

                  if not End_Found then
                     File_Upload (Start_Boundary, End_Boundary, False);
                  end if;

               else
                  --  There is no file for this multipart, user did not enter
                  --  something in the field.

                  File_Upload (Start_Boundary, End_Boundary, True);
               end if;

            else
               --  This part of the multipart message contains field values

               declare
                  Value : Unbounded_String;
               begin
                  loop
                     declare
                        L : constant String := Net.Buffered.Get_Line (Sock);
                     begin
                        End_Found := (L = End_Boundary);

                        exit when End_Found or else L = Start_Boundary;

                        --  Append this line to the value

                        if Value /= Null_Unbounded_String then
                           Append (Value, ASCII.CR & ASCII.LF);
                        end if;
                        Append (Value, L);
                     end;
                  end loop;

                  Status.Set.Add_Parameter
                    (C_Stat,
                     To_String (Name),
                     To_String (Value),
                     Decode => False);
                  --  Do not decode values for multipart/form-data
               end;

               if not End_Found then
                  File_Upload (Start_Boundary, End_Boundary, False);
               end if;
            end if;
         end if;
      end File_Upload;

      -------------------
      -- Get_File_Data --
      -------------------

      procedure Get_File_Data
        (Server_Filename : String;
         Filename        : String;
         Start_Boundary  : String;
         Mode            : Message_Mode;
         Headers         : AWS.Headers.List;
         End_Found       : out Boolean)
      is
         type Error_State is (No_Error, Name_Error, Device_Error);
         --  This state is to monitor the file upload process. If we receice
         --  Name_Error or Device_Error while writing data on disk we need to
         --  continue reading all data from the socket if we want to be able
         --  to send back an error message.

         function Check_EOF return Boolean;
         --  Returns True if we have reach the end of file data

         procedure Write
           (Buffer : Streams.Stream_Element_Array; Trim : Boolean);
         pragma Inline (Write);
         --  Write buffer to the file, handle the Device_Error exception

         File    : Streams.Stream_IO.File_Type;
         Buffer  : Streams.Stream_Element_Array (1 .. 4 * 1_024);
         Index   : Streams.Stream_Element_Offset := Buffer'First;

         Data    : Streams.Stream_Element_Array (1 .. 1);
         Data2   : Streams.Stream_Element_Array (1 .. 2);
         Error   : Error_State := No_Error;

         ---------------
         -- Check_EOF --
         ---------------

         function Check_EOF return Boolean is

            Signature : constant Streams.Stream_Element_Array
              := (1 => 13, 2 => 10)
                   & Translator.To_Stream_Element_Array (Start_Boundary);

            Buffer : Streams.Stream_Element_Array (1 .. Signature'Length);
            Index  : Streams.Stream_Element_Offset := Buffer'First;

            procedure Write_Data;
            --  Put buffer data into the main buffer (Get_Data.Buffer). If
            --  the main buffer is not big enough, it will write the buffer
            --  into the file before.

            ----------------
            -- Write_Data --
            ----------------

            procedure Write_Data is
            begin
               if Error /= No_Error then
                  return;
               end if;

               if Get_File_Data.Buffer'Last
                 < Get_File_Data.Index + Index - 1
               then
                  Write (Get_File_Data.Buffer
                           (Get_File_Data.Buffer'First
                              .. Get_File_Data.Index - 1), False);
                  Get_File_Data.Index := Get_File_Data.Buffer'First;
               end if;

               Get_File_Data.Buffer
                 (Get_File_Data.Index .. Get_File_Data.Index + Index - 2)
                 := Buffer (Buffer'First .. Index - 1);

               Get_File_Data.Index := Get_File_Data.Index + Index - 1;
            end Write_Data;

         begin -- Check_EOF
            Buffer (Index) := 13;
            Index := Index + 1;

            loop
               Net.Buffered.Read (Sock, Data);

               if Data (1) = 13 then
                  Write_Data;
                  return False;
               end if;

               Buffer (Index) := Data (1);

               if Index = Buffer'Last then
                  if Buffer = Signature then
                     return True;
                  else
                     Write_Data;
                     return False;
                  end if;
               end if;

               Index := Index + 1;
            end loop;
         end Check_EOF;

         -----------
         -- Write --
         -----------

         procedure Write
           (Buffer : Streams.Stream_Element_Array; Trim : Boolean) is
         begin
            if Error = No_Error then
               if Mode in Attachment .. File_Upload then
                  Streams.Stream_IO.Write (File, Buffer);
               else
                  --  This is the root part of an MIME attachment, append the
                  --  data to the status record.
                  Status.Set.Append_Body (C_Stat, Buffer, Trim);
               end if;
            end if;
         exception
            when Text_IO.Device_Error =>
               Error := Device_Error;
         end Write;

      begin
         begin
            if Mode in Attachment .. File_Upload then
               Streams.Stream_IO.Create
                 (File, Streams.Stream_IO.Out_File, Server_Filename);
            end if;
         exception
            when Text_IO.Name_Error =>
               Error := Name_Error;
         end;

         Read_File : loop
            Net.Buffered.Read (Sock, Data);

            while Data (1) = 13 loop
               exit Read_File when Check_EOF;
            end loop;

            Buffer (Index) := Data (1);
            Index := Index + 1;

            if Index > Buffer'Last then
               Write (Buffer, False);
               Index := Buffer'First;

               HTTP_Server.Slots.Check_Data_Timeout (Line_Index);
            end if;
         end loop Read_File;

         if Index /= Buffer'First then
            Write (Buffer (Buffer'First .. Index - 1), True);
         end if;

         if Error = No_Error then
            case Mode is
               when Root_Attachment =>
                  null;

               when Attachment =>
                  Streams.Stream_IO.Close (File);
                  AWS.Attachments.Add
                    (Attachments, Server_Filename, Headers, Filename);

               when File_Upload =>
                  Streams.Stream_IO.Close (File);
            end case;
         end if;

         --  Check for end-boundary, at this point we have at least two
         --  chars. Either the terminating "--" or CR+LF.

         Net.Buffered.Read (Sock, Data2);

         if Data2 (2) = 10 then
            --  We have CR+LF, it is a start-boundary
            End_Found := False;

         else
            --  We have read the "--", read line terminator. This is the
            --  end-boundary.

            End_Found := True;
            Net.Buffered.Read (Sock, Data2);
         end if;

         if Error = Name_Error then
            --  We can't create the file, add a clear exception message
            raise HTTP_Utils.Name_Error
              with "Cannot create file " & Server_Filename;

         elsif Error = Device_Error then
            --  We can't write to the file, there is probably no space left
            --  on devide.
            raise HTTP_Utils.Device_Error
              with "No space left on device while writting " & Server_Filename;
         end if;
      end Get_File_Data;

      -----------------------
      -- Store_Attachments --
      -----------------------

      procedure Store_Attachments
        (Start_Boundary, End_Boundary : String;
         Parse_Boundary               : Boolean;
         Root_Part_CID                : String)
      is
         Server_Filename : Unbounded_String;
         Content_Id      : Unbounded_String;
         Headers         : AWS.Headers.List;

         End_Found       : Boolean := False;
         --  Set to true when the end-boundary has been found

         function Attachment_Filename (Extension : String) return String;
         --  Returns the full path name for the file as stored on the
         --  server side.

         -------------------------
         -- Attachment_Filename --
         -------------------------

         function Attachment_Filename (Extension : String) return String is
            Upload_Path : constant String :=
                            CNF.Upload_Directory (HTTP_Server.Properties);
            UID         : Natural;
         begin
            File_Upload_UID.Get (UID);

            if Extension = "" then
               return Upload_Path & Utils.Image (UID);
            else
               return Upload_Path & Utils.Image (UID) & '.' & Extension;
            end if;
         end Attachment_Filename;

      begin -- Store_Attachments
         --  Reach the boundary

         if Parse_Boundary then
            loop
               declare
                  Data : constant String := Net.Buffered.Get_Line (Sock);
               begin
                  exit when Data = Start_Boundary;

                  if Data = End_Boundary then
                     --  This is the end of the multipart data
                     return;
                  end if;
               end;
            end loop;
         end if;

         --  Read header

         AWS.Headers.Set.Read (Sock, Headers);

         if AWS.Headers.Get_Values
           (Headers, Messages.Content_Type_Token) = MIME.Application_Form_Data
         then
            --  This chunk is the form parameter
            Status.Set.Read_Body
              (Sock, C_Stat,
               Boundary => "--" & To_String (Status_Multipart_Boundary));

            --  Skip CRLF after boundary

            declare
               Data : constant String := Net.Buffered.Get_Line (Sock);
               pragma Unreferenced (Data);
            begin
               null;
            end;

            Status.Set.Parameters_From_Body (C_Stat);

            Store_Attachments
              (Start_Boundary, End_Boundary, False, Root_Part_CID);

         else
            Content_Id := To_Unbounded_String
              (AWS.Headers.Get (Headers, Messages.Content_Id_Token));

            --  Read file/field data

            if Content_Id = Status_Root_Part_CID then
               Get_File_Data
                 ("", "", Start_Boundary, Root_Attachment, Headers, End_Found);

            else
               Server_Filename := To_Unbounded_String
                 (Attachment_Filename
                    (AWS.MIME.Extension
                       (AWS.Headers.Values.Get_Unnamed_Value
                          (AWS.Headers.Get
                             (Headers, Messages.Content_Type_Token)))));

               Get_File_Data
                 (To_String (Server_Filename), To_String (Server_Filename),
                  Start_Boundary, Attachment, Headers, End_Found);
            end if;

            --  More attachments ?

            if End_Found then
               AWS.Status.Set.Attachments (C_Stat, Attachments);
            else
               Store_Attachments
                 (Start_Boundary, End_Boundary, False, Root_Part_CID);
            end if;
         end if;
      end Store_Attachments;

   begin -- Get_Message_Data
      if Expect_100 then
         Net.Buffered.Put_Line (Sock, Messages.Status_Line (Messages.S100));
         Net.Buffered.New_Line (Sock);
         Net.Buffered.Flush (Sock);
      end if;

      --  Get necessary data from header for reading HTTP body

      declare

         procedure Named_Value
           (Name, Value : String; Quit : in out Boolean);
         --  Looking for the Boundary value in the  Content-Type header line

         procedure Value (Item : String; Quit : in out Boolean);
         --  Reading the first unnamed value into the Status_Content_Type
         --  variable from the Content-Type header line.

         -----------------
         -- Named_Value --
         -----------------

         procedure Named_Value
           (Name, Value : String; Quit : in out Boolean)
         is
            pragma Unreferenced (Quit);
            L_Name : constant String :=
                        Ada.Characters.Handling.To_Lower (Name);
         begin
            if L_Name = "boundary" then
               Status_Multipart_Boundary := To_Unbounded_String (Value);
            elsif L_Name = "start" then
               Status_Root_Part_CID := To_Unbounded_String (Value);
            end if;
         end Named_Value;

         -----------
         -- Value --
         -----------

         procedure Value (Item : String; Quit : in out Boolean) is
         begin
            if Status_Content_Type /= Null_Unbounded_String then
               --  Only first unnamed value is the Content_Type

               Quit := True;

            elsif Item'Length > 0 then
               Status_Content_Type := To_Unbounded_String (Item);
            end if;
         end Value;

         procedure Parse is new Headers.Values.Parse (Value, Named_Value);

      begin
         --  Clear Content-Type status as this could have already been set
         --  in previous request.

         Status_Content_Type := Null_Unbounded_String;

         Parse (Status.Content_Type (C_Stat));
      end;

      if Status.Method (C_Stat) = Status.POST
        and then Status_Content_Type = MIME.Application_Form_Data
      then
         --  Read data from the stream and convert it to a string as
         --  these are a POST form parameters.
         --  The body has the format: name1=value1&name2=value2...

         Status.Set.Read_Body (Sock, C_Stat);

         Status.Set.Parameters_From_Body (C_Stat);

      elsif Status.Method (C_Stat) = Status.POST
        and then Status_Content_Type = MIME.Multipart_Form_Data
      then
         --  This is a file upload

         File_Upload
           ("--" & To_String (Status_Multipart_Boundary),
            "--" & To_String (Status_Multipart_Boundary) & "--",
            True);

      elsif Status.Method (C_Stat) = Status.POST
        and then Status_Content_Type = MIME.Multipart_Related
      then
         --  Attachments are to be written to separate files

         Store_Attachments
           ("--" & To_String (Status_Multipart_Boundary),
            "--" & To_String (Status_Multipart_Boundary) & "--",
            True,
            To_String (Status_Root_Part_CID));

      else
         --  Let's suppose for now that all others content type data are
         --  binary data.

         Status.Set.Read_Body (Sock, C_Stat);
      end if;

      Status.Reset_Body_Index (C_Stat);

      HTTP_Server.Slots.Mark_Phase (Line_Index, Server_Processing);
      Status.Set.Uploaded (C_Stat);
   end Get_Message_Data;

   ----------------------
   -- Get_Request_Line --
   ----------------------

   procedure Get_Request_Line (C_Stat : in out AWS.Status.Data) is
      Sock : constant Net.Socket_Type'Class := Status.Socket (C_Stat);
   begin
      --  Get and parse request line

      loop
         declare
            Data : constant String := Net.Buffered.Get_Line (Sock);
         begin
            --  RFC 2616
            --  4.1 Message Types
            --  ....................
            --  In the interest of robustness, servers SHOULD ignore any empty
            --  line(s) received where a Request-Line is expected.

            if Data /= "" then
               Parse_Request_Line (Data, C_Stat);
               exit;
            end if;
         end;
      end loop;
   end Get_Request_Line;

   ------------------------
   -- Is_Valid_HTTP_Date --
   ------------------------

   function Is_Valid_HTTP_Date (HTTP_Date : String) return Boolean is
      Mask   : constant String  := "Aaa, 99 Aaa 9999 99:99:99 GMT";
      Offset : constant Integer := HTTP_Date'First - 1;
      --  Make sure the function works for inputs with 'First <> 1
      Result : Boolean := True;
   begin
      for I in Mask'Range loop
         Result := I + Offset in HTTP_Date'Range;

         exit when not Result;

         case Mask (I) is
            when 'A' =>
               Result := HTTP_Date (I + Offset) in 'A' .. 'Z';

            when 'a' =>
               Result := HTTP_Date (I + Offset) in 'a' .. 'z';

            when '9' =>
               Result := HTTP_Date (I + Offset) in '0' .. '9';

            when others =>
               Result := Mask (I) = HTTP_Date (I + Offset);
         end case;
      end loop;

      return Result;
   end Is_Valid_HTTP_Date;

   ------------------------
   -- Parse_Request_Line --
   ------------------------

   procedure Parse_Request_Line
     (Command : String;
      C_Stat  : in out AWS.Status.Data)
   is

      I1, I2 : Natural;
      --  Index of first space and second space

      I3 : Natural;
      --  Index of ? if present in the URI (means that there is some
      --  parameters)

      procedure Cut_Command;
      --  Parse Command and set I1, I2 and I3

      function Method return String;
      pragma Inline (Method);
      --  Returns the method

      function Resource return String;
      pragma Inline (Resource);
      --  Returns first parameter. parameters are separated by spaces

      function Parameters return String;
      --  Returns parameters if some where specified in the URI

      function HTTP_Version return String;
      pragma Inline (HTTP_Version);
      --  Returns second parameter. parameters are separated by spaces

      -----------------
      -- Cut_Command --
      -----------------

      procedure Cut_Command is
      begin
         I1  := Fixed.Index (Command, " ");
         I2  := Fixed.Index (Command (I1 + 1 .. Command'Last), " ", Backward);

         I3  := Fixed.Index (Command (I1 + 1 .. I2 - 1), "?");

         if I1 = 0 or else I2 = 0 or else I1 = I2 then
            raise Constraint_Error with "Wrong request line '" & Command & ''';

         elsif I3 = 0 then
            --  Could be encoded ?

            I3  := Fixed.Index (Command (I1 + 1 .. I2 - 1), "%3f");

            if I3 = 0 then
               I3  := Fixed.Index (Command (I1 + 1 .. I2 - 1), "%3F");
            end if;
         end if;
      end Cut_Command;

      ------------------
      -- HTTP_Version --
      ------------------

      function HTTP_Version return String is
      begin
         return Command (I2 + 1 .. Command'Last);
      end HTTP_Version;

      ------------
      -- Method --
      ------------

      function Method return String is
      begin
         return Command (Command'First .. I1 - 1);
      end Method;

      ----------------
      -- Parameters --
      ----------------

      function Parameters return String is
      begin
         if I3 = 0 then
            return "";
         else
            if Command (I3) = '%' then
               return Command (I3 + 3 .. I2 - 1);
            else
               return Command (I3 + 1 .. I2 - 1);
            end if;
         end if;
      end Parameters;

      --------------
      -- Resource --
      --------------

      function Resource return String is
      begin
         if I3 = 0 then
            return URL.Decode (Command (I1 + 1 .. I2 - 1));
         else
            return URL.Decode (Command (I1 + 1 .. I3 - 1));
         end if;
      end Resource;

   begin
      Cut_Command;

      --  GET and HEAD can have a set of parameters (query) attached. This is
      --  not really standard see [RFC 2616 - 13.9] but is widely used now.
      --
      --  POST parameters are passed into the message body, but we allow
      --  parameters also in this case. It is not clear if it is permitted or
      --  prohibited by reading RFC 2616. Other technologies do offer this
      --  feature so AWS do this as well.

      Status.Set.Request (C_Stat, Method, Resource, HTTP_Version);

      Status.Set.Add_Parameters (C_Stat, Parameters);
   end Parse_Request_Line;

   ----------
   -- Send --
   ----------

   procedure Send
     (Answer       : in out Response.Data;
      HTTP_Server  : in out AWS.Server.HTTP;
      Line_Index   : Positive;
      C_Stat       : AWS.Status.Data;
      Socket_Taken : in out Boolean;
      Will_Close   : in out Boolean)
   is
      LA : constant Line_Attribute.Attribute_Handle :=
        Line_Attribute.Reference;

      use type Response.Data_Mode;

      Status_Code : Messages.Status_Code;
      Length      : Resources.Content_Length_Type := 0;

      procedure Send_General_Header (Sock : Net.Socket_Type'Class);
      --  Send the "Date:", "Server:", "Set-Cookie:" and "Connection:" header

      procedure Send_Header_Only;
      --  Send HTTP message header only. This is used to implement the HEAD
      --  request.

      procedure Send_Data;
      --  Send a text/binary data to the client

      ---------------
      -- Send_Data --
      ---------------

      procedure Send_Data is
         use type Calendar.Time;
         use type AWS.Status.Request_Method;

         Sock          : constant Net.Socket_Type'Class :=
                           Status.Socket (C_Stat);
         Method        : constant AWS.Status.Request_Method :=
                           Status.Method (C_Stat);
         Filename      : constant String :=
                           Response.Filename (Answer);
         File_Mode     : constant Boolean :=
                           Response.Mode (Answer) = Response.File;

         Is_Up_To_Date : Boolean := False;
         File          : Resources.File_Type;
         File_Time     : Ada.Calendar.Time;
      begin
         if File_Mode then
            File_Time := Resources.File_Timestamp (Filename);

            Is_Up_To_Date
              := Is_Valid_HTTP_Date (Status.If_Modified_Since (C_Stat))
                    and then
                 File_Time
                   = Messages.To_Time (Status.If_Modified_Since (C_Stat));
            --  Equal used here see [RFC 2616 - 14.25]
         end if;

         if Is_Up_To_Date then
            --  [RFC 2616 - 10.3.5]
            Net.Buffered.Put_Line
              (Sock, Messages.Status_Line (Messages.S304));

            Send_General_Header (Sock);
            Net.Buffered.New_Line (Sock);
            Net.Buffered.Flush (Sock);
            return;

         elsif Headers.Get_Values
           (Status.Header (C_Stat), Messages.Range_Token) /= ""
         then
            --  Partial range request, answer accordingly
            Net.Buffered.Put_Line (Sock, Messages.Status_Line (Messages.S206));

         else
            Net.Buffered.Put_Line (Sock, Messages.Status_Line (Status_Code));
         end if;

         --  Note. We have to call Create_Resource before send header fields
         --  defined in the Answer to the client, because this call could
         --  setup Content-Encoding header field to Answer. Answer header
         --  lines would be send below in the Send_General_Header.

         Response.Create_Resource
           (Answer, File, AWS.Status.Is_Supported (C_Stat, Messages.GZip));

         --  Length is the real resource/file size

         Length := Resources.Size (File);

         --  Checking if we have to close connection because of undefined
         --  message length comming from a user's stream.

         if Length = Resources.Undefined_Length
           and then Status.HTTP_Version (C_Stat) = HTTP_10
         --  We cannot use transfer-encoding chunked in HTTP_10
           and then Method /= Status.HEAD
         --  We have to send message_body
         then
            --  In this case we need to close the connection explicitly at the
            --  end of the transfer.
            Will_Close := True;
         end if;

         Send_General_Header (Sock);

         --  Send file last-modified timestamp info in case of a file

         if File_Mode then
            Net.Buffered.Put_Line (Sock, Messages.Last_Modified (File_Time));
         end if;

         --  Note that we cannot send the Content_Length header at this
         --  point. A server should not send Content_Length if the
         --  transfer-coding used is not identity. This is allowed by the
         --  RFC but it seems that some implementation does not handle this
         --  right. The file can be sent using either identity or chunked
         --  transfer-coding. The proper header will be sent in Send_Resource
         --  see [RFC 2616 - 4.4].

         --  Send message body

         Send_Resource
           (Method, Response.Close_Resource (Answer), File, Length,
            HTTP_Server, Line_Index, C_Stat);
         Net.Buffered.Flush (Sock);
      end Send_Data;

      -------------------------
      -- Send_General_Header --
      -------------------------

      procedure Send_General_Header (Sock : Net.Socket_Type'Class) is
         use type Messages.Cache_Option;
      begin
         --  Session

         if CNF.Session (HTTP_Server.Properties)
           and then AWS.Status.Session_Created (C_Stat)
         then
            --  This is an HTTP connection with session but there is no session
            --  ID set yet. So, send cookie to client browser.

            Response.Set.Update_Header
              (D     => Answer,
               Name  => Messages.Set_Cookie_Token,
               Value => CNF.Session_Name (HTTP_Server.Properties) & '='
                        & Session.Image (AWS.Status.Session (C_Stat))
                        & "; path=/; Version=1");
         end if;

         --  Date

         Net.Buffered.Put_Line
           (Sock, "Date: " & Messages.To_HTTP_Date (Utils.GMT_Clock));

         --  Server

         Net.Buffered.Put_Line
           (Sock, "Server: AWS (Ada Web Server) v" & Version);

         if Will_Close then
            --  We have decided to close connection after answering the client
            Response.Set.Update_Header
              (Answer, Messages.Connection_Token, Value => "close");

         else
            Response.Set.Update_Header
              (Answer, Messages.Connection_Token, Value => "keep-alive");
         end if;

         --  Send Content-Type, Cache-Control, Location, WWW-Authenticate
         --  and others user defined header lines.

         Response.Send_Header (Socket => Sock, D => Answer);
      end Send_General_Header;

      ----------------------
      -- Send_Header_Only --
      ----------------------

      procedure Send_Header_Only is
         use type AWS.Status.Request_Method;
         Sock : constant Net.Socket_Type'Class := Status.Socket (C_Stat);
      begin
         --  First let's output the status line

         Net.Buffered.Put_Line (Sock, Messages.Status_Line (Status_Code));

         Send_General_Header (Sock);

         --  There is no content

         Net.Buffered.Put_Line (Sock, Messages.Content_Length (0));

         --  End of header

         Net.Buffered.New_Line (Sock);
         Net.Buffered.Flush (Sock);
      end Send_Header_Only;

      use type Response.Data;

   begin
      Status_Code := Response.Status_Code (Answer);

      case Response.Mode (Answer) is

         when Response.File | Response.File_Once | Response.Stream
              | Response.Message =>
            HTTP_Server.Slots.Mark_Phase (Line_Index, Server_Response);
            Send_Data;

         when Response.Header =>
            HTTP_Server.Slots.Mark_Phase (Line_Index, Server_Response);
            Send_Header_Only;

         when Response.Socket_Taken =>
            HTTP_Server.Slots.Socket_Taken (Line_Index);
            Socket_Taken := True;

         when Response.No_Data =>
            raise Constraint_Error
              with "Answer not properly initialized (No_Data)";
      end case;

      if LA.Skip_Log then
         LA.Skip_Log := False;

      elsif CNF.Log_Extended_Fields_Length (HTTP_Server.Properties) > 0 then
         declare
            use Real_Time;
            use type Strings.Maps.Character_Set;
         begin
            Log.Set_Field
              (LA.Server.Log, LA.Log_Data, "time-taken",
               Utils.Significant_Image
                 (To_Duration (Clock - Status.Request_Time (C_Stat)), 3));

            Log.Set_Header_Fields
              (LA.Server.Log, LA.Log_Data, "cs", Status.Header (C_Stat));
            Log.Set_Header_Fields
              (LA.Server.Log, LA.Log_Data, "sc", Response.Header (Answer));

            Log.Set_Field
              (LA.Server.Log, LA.Log_Data, "cs-method",
               Status.Method (C_Stat));
            Log.Set_Field
              (LA.Server.Log, LA.Log_Data, "cs-username",
               Status.Authorization_Name (C_Stat));
            Log.Set_Field
              (LA.Server.Log, LA.Log_Data, "cs-version",
               Status.HTTP_Version (C_Stat));

            declare
               use AWS.URL;

               Encoding : constant Strings.Maps.Character_Set :=
                            Strings.Maps.To_Set
                              (Span => (Low  => Character'Val (128),
                                        High => Character'Last))
                            or Strings.Maps.To_Set ("+"" ");

               URI      : constant String :=
                            Encode (Status.URI (C_Stat), Encoding);

               Query    : constant String :=
                            Parameters.URI_Format
                              (Status.Parameters (C_Stat));
            begin
               Log.Set_Field (LA.Server.Log, LA.Log_Data, "cs-uri-stem", URI);
               Log.Set_Field
                 (LA.Server.Log, LA.Log_Data, "cs-uri-query", Query);
               Log.Set_Field
                 (LA.Server.Log, LA.Log_Data, "cs-uri", URI & Query);
            end;

            Log.Set_Field
              (LA.Server.Log, LA.Log_Data, "sc-status",
               Messages.Image (Status_Code));
            Log.Set_Field
              (LA.Server.Log, LA.Log_Data, "sc-bytes",
               Utils.Image (Integer (Length)));

            Log.Write (LA.Server.Log, LA.Log_Data);
         end;

      else
         Log.Write (HTTP_Server.Log, C_Stat, Status_Code, Integer (Length));
      end if;
   end Send;

   -------------------
   -- Send_Resource --
   -------------------

   procedure Send_Resource
     (Method      : Status.Request_Method;
      Close       : Boolean;
      File        : in out Resources.File_Type;
      Length      : in out Resources.Content_Length_Type;
      HTTP_Server : AWS.Server.HTTP;
      Line_Index  : Positive;
      C_Stat      : AWS.Status.Data)
   is
      use type Status.Request_Method;

      Sock        : constant Net.Socket_Type'Class := Status.Socket (C_Stat);

      Buffer_Size : constant := 4 * 1_024;
      --  Size of the buffer used to send the file

      Chunk_Size  : constant := 1_024;
      --  Size of the buffer used to send the file with the chunked encoding.
      --  This is the maximum size of each chunk.

      Ranges      : constant String :=
                      Headers.Get_Values
                        (Status.Header (C_Stat), Messages.Range_Token);
      --  The ranges for partial sending if defined

      procedure Send_File;
      --  Send file in one part

      procedure Send_Ranges;
      --  Send a set of ranges of file content

      procedure Send_File_Chunked;
      --  Send file in chunks, used in HTTP/1.1 and when the message length
      --  is not known)

      Last : Streams.Stream_Element_Offset;

      ---------------
      -- Send_File --
      ---------------

      procedure Send_File is
         Buffer : Streams.Stream_Element_Array (1 .. Buffer_Size);

      begin
         loop
            Resources.Read (File, Buffer, Last);

            exit when Last < Buffer'First;

            Net.Buffered.Write (Sock, Buffer (1 .. Last));

            Length := Length + Last;

            HTTP_Server.Slots.Check_Data_Timeout (Line_Index);
         end loop;
      end Send_File;

      ---------------------
      -- Send_File_Chunk --
      ---------------------

      procedure Send_File_Chunked is
         --  Note that we do not use a buffered socket here. Opera on SSL
         --  sockets does not like chunk that are not sent in a whole.

         Buffer : Streams.Stream_Element_Array (1 .. Chunk_Size);
         --  Each chunk will have a maximum length of Buffer'Length

         CRLF : constant Streams.Stream_Element_Array
           := (1 => Character'Pos (ASCII.CR), 2 => Character'Pos (ASCII.LF));

         Last_Chunk : constant Streams.Stream_Element_Array
           := Character'Pos ('0') & CRLF & CRLF;
         --  Last chunk for a chunked encoding stream. See [RFC 2616 - 3.6.1]

      begin
         Send_Chunks : loop
            Resources.Read (File, Buffer, Last);

            if Last = 0 then
               --  There is not more data to read, the previous chunk was the
               --  last one, just terminate the chunk message here.
               Net.Send (Sock, Last_Chunk);
               exit Send_Chunks;
            end if;

            Length := Length + Last;

            HTTP_Server.Slots.Check_Data_Timeout (Line_Index);

            declare
               H_Last : constant String := Utils.Hex (Positive (Last));

               Chunk  : constant Streams.Stream_Element_Array :=
                          Translator.To_Stream_Element_Array (H_Last)
                          & CRLF & Buffer (1 .. Last) & CRLF;
               --  A chunk is composed of:
               --     the Size of the chunk in hexadecimal
               --     a line feed
               --     the chunk
               --     a line feed

            begin
               --  Check if the last data portion

               if Last < Buffer'Last then
                  --  No more data, add the terminating chunk
                  Net.Send (Sock, Chunk & Last_Chunk);
                  exit Send_Chunks;
               else
                  Net.Send (Sock, Chunk);
               end if;
            end;
         end loop Send_Chunks;
      end Send_File_Chunked;

      -----------------
      -- Send_Ranges --
      -----------------

      procedure Send_Ranges is

         Boundary    : constant String := "aws_range_separator";
         N_Range     : constant Positive := 1 + Fixed.Count (Ranges, ",");
         N_Minus     : constant Natural  := Fixed.Count (Ranges, "-");
         --  Number of ranges defined
         Equal       : constant Natural := Fixed.Index (Ranges, "=");
         First, Last : Positive;

         procedure Send_Range (R : String);
         --  Send a single range as defined by R

         ----------------
         -- Send_Range --
         ----------------

         procedure Send_Range (R : String) is
            I_Minus  : constant Positive := Fixed.Index (R, "-");
            First    : Stream_Element_Offset;
            Last     : Stream_Element_Offset;
            R_Length : Stream_Element_Offset;
         begin
            if N_Range /= 1 then
               --  Send the multipart/byteranges
               Net.Buffered.Put_Line (Sock, "--" & Boundary);
            end if;

            --  Computer First / Last and the range length

            if R (I_Minus + 1 .. R'Last) = "" then
               Last := Length - 1;
            else
               Last := Stream_Element_Offset'Value
                 (R (I_Minus + 1 .. R'Last));
            end if;

            if R (R'First .. I_Minus - 1) = "" then
               --  In this case we want to get the last N bytes from the file
               First := Length - Last;
               Last := Length - 1;
            else
               First := Stream_Element_Offset'Value
                 (R (R'First .. I_Minus - 1));
            end if;

            R_Length := Last - First + 1;

            --  Content-Range: bytes <first>-<last>/<length>

            Net.Buffered.Put_Line
              (Sock, Messages.Content_Range_Token & ": bytes "
               & Utils.Image (Natural (First)) & "-"
               & Utils.Image (Natural (Last))
               & "/" & Utils.Image (Natural (Length)));
            Net.Buffered.Put_Line
              (Sock, Messages.Content_Length (Positive (R_Length)));
            Net.Buffered.New_Line (Sock);

            Resources.Set_Index (File, First + 1);

            declare
               Buffer : Streams.Stream_Element_Array (1 .. Buffer_Size);
               Sent   : Stream_Element_Offset := 0;
               Size   : Stream_Element_Offset := 0;
               Last   : Stream_Element_Offset;
            begin
               loop
                  Size := Stream_Element_Offset'Min
                    (R_Length - Sent, Buffer_Size);

                  exit when Size = 0;

                  Resources.Read (File, Buffer (1 .. Size), Last);

                  exit when Last < Buffer'First;

                  Net.Buffered.Write (Sock, Buffer (1 .. Last));

                  Sent := Sent + Last;

                  HTTP_Server.Slots.Check_Data_Timeout (Line_Index);
               end loop;
            end;
         end Send_Range;

      begin
         --  Check range definition
         if N_Range /= N_Minus
           or else Equal = 0
           or else Ranges (Ranges'First .. Equal - 1) /= "bytes"
         then
            --  Range is wrong, let's send the whole file then
            Send_File;
         end if;

         if N_Range /= 1 then
            --  Then we will send a multipart/byteranges
            Net.Buffered.Put_Line
              (Sock,
               Messages.Content_Type
                 (MIME.Multipart_Byteranges & "; boundary=" & Boundary));
         end if;

         First := Equal + 1;

         for K in 1 .. N_Range loop
            if K = N_Range then
               Last := Ranges'Last;
            else
               Last := Fixed.Index (Ranges (First .. Ranges'Last), ",") - 1;
            end if;

            Send_Range (Ranges (First .. Last));
            First := Last + 2;
         end loop;

         --  End the multipart/byteranges message

         if N_Range /= 1 then
            --  Send the multipart/byteranges
            Net.Buffered.Put_Line (Sock, "--" & Boundary & "--");
         end if;
      end Send_Ranges;

   begin
      if Ranges /= "" and then Length /= Resources.Undefined_Length then
         --  Range: header present, we need to send only the specified bytes

         Net.Buffered.Put_Line
           (Sock, Messages.Accept_Ranges_Token & ": bytes");
         --  Only bytes supported

         Send_Ranges;

      elsif Status.HTTP_Version (C_Stat) = HTTP_10
        or else Length /= Resources.Undefined_Length
      then
         --  If content length is undefined and we handle an HTTP/1.0 protocol
         --  then the end of the stream will be determined by closing the
         --  connection. [RFC 1945 - 7.2.2] See the Will_Close local variable.

         if Length /= Resources.Undefined_Length then
            Net.Buffered.Put_Line
              (Sock, Messages.Content_Length (Natural (Length)));
         end if;

         --  Terminate header

         Net.Buffered.New_Line (Sock);

         if Method /= Status.HEAD and then Length /= 0 then
            Length := 0;
            Send_File;
         end if;

      else
         --  HTTP/1.1 case and we do not know the message length
         --
         --  Terminate header, do not send the Content_Length see
         --  [RFC 2616 - 4.4]. It could be possible to send the Content_Length
         --  as this is cleary a permission but it does not work in some
         --  obsucre cases.

         Net.Buffered.Put_Line (Sock, Messages.Transfer_Encoding ("chunked"));
         Net.Buffered.New_Line (Sock);
         Net.Buffered.Flush (Sock);

         --  Past this point we will not use the buffered mode. Opera on SSL
         --  sockets does not like chunk that are not sent in a whole.

         if Method /= Status.HEAD then
            Length := 0;
            Send_File_Chunked;
         end if;
      end if;

      if Close then
         Resources.Close (File);
      end if;

   exception
      when others =>
         if Close then
            Resources.Close (File);
         end if;
         raise;
   end Send_Resource;

   ----------------------
   -- Set_Close_Status --
   ----------------------

   procedure Set_Close_Status
     (C_Stat     : AWS.Status.Data;
      Keep_Alive : Boolean;
      Will_Close : in out Boolean)
   is
      Connection : constant String := Status.Connection (C_Stat);
   begin
      --  Connection, check connection string with Match to skip connection
      --  options [RFC 2616 - 14.10].

      Will_Close := AWS.Messages.Match (Connection, "close")
        or else not Keep_Alive
        or else (Status.HTTP_Version (C_Stat) = HTTP_10
                 and then
                 AWS.Messages.Does_Not_Match (Connection, "keep-alive"));
   end Set_Close_Status;

end AWS.Server.HTTP_Utils;