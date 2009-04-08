------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                     Copyright (C) 2007-2009, AdaCore                     --
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

with Ada.Text_IO;
with Ada.Strings.Fixed;

with AWS.Client;
with AWS.Parameters;
with AWS.Server;
with AWS.Response;
with AWS.Status;
with AWS.MIME;
with AWS.URL;
with AWS.Utils;

with Get_Free_Port;

procedure URL_Object is

   use Ada;
   use AWS;

   WS : Server.HTTP;

   Port : Natural := 1234;

   function CB (Request : Status.Data) return Response.Data is
      U : constant URL.Object := Status.URI (Request);
      P : constant Parameters.List := Status.Parameters (Request);

      URL_Image  : String := URL.URL (U);
      Port_Image : constant String  := Utils.Image (Port);
      Port_Idx   : constant Natural :=
        Strings.Fixed.Index (URL_Image, ':' & Port_Image & '/');

   begin
      URL_Image (Port_Idx + 1 .. Port_Idx + Port_Image'Length) := "port";

      Text_IO.Put_Line ("p1=" & Parameters.Get (P, "p1"));
      Text_IO.Put_Line ("p2=" & Parameters.Get (P, "p2"));
      Text_IO.Put_Line ("----------------------");
      Text_IO.Put_Line ("p1=" & Status.Parameter (Request, "p1"));
      Text_IO.Put_Line ("p2=" & Status.Parameter (Request, "p2"));
      Text_IO.Put_Line ("----------------------");
      Text_IO.Put_Line ("URI         = " & Status.URI (Request));
      Text_IO.Put_Line ("URL         = " & URL_Image);
      Text_IO.Put_Line ("Query       = " & URL.Query (U));
      Text_IO.Put_Line ("Path        = " & URL.Path (U));
      Text_IO.Put_Line ("Pathname    = " & URL.Pathname (U));
      Text_IO.Put_Line ("File        = " & URL.File (U));
      Text_IO.Put_Line ("Parameters  = " & URL.Parameters (U));
      Text_IO.Put_Line ("Server_Name = " & URL.Server_Name (U));

      if URL.Port (U) /= Port or else URL.Port (U) /= Port_Image then
         Text_IO.Put_Line ("URL.Port error");
      end if;

      return Response.Build (MIME.Text_HTML, "not used");
   end CB;

   R    : Response.Data;

begin
   Get_Free_Port (Port);

   Server.Start (WS, "url_object", CB'Unrestricted_Access, Port => Port);
   Text_IO.Put_Line ("started"); Ada.Text_IO.Flush;

   R := Client.Get
     ("http://localhost:" & Utils.Image (Port) & "/get_it?p1=1&p2=toto");

   R := Client.Get
     ("http://localhost:" & Utils.Image (Port)
      & "/get_it/disk.html?p1=0956&p2=uuu");

   Server.Shutdown (WS);
   Text_IO.Put_Line ("shutdown");
end URL_Object;
