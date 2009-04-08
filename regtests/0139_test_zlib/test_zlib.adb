------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                     Copyright (C) 2000-2009, AdaCore                     --
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

--  The program has a few aims.
--  1. Test ZLib Ada thick binding functionality.
--  2. Show the example of use main functionality of the ZLib Ada binding.
--  3. Build this program automatically compile all ZLib.* packages under
--     GNAT compiler.

with Ada.Numerics.Discrete_Random;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;

with ZLib.Streams;

procedure Test_Zlib is

   use Ada;
   use Ada.Streams;
   use Stream_IO;

   ------------------------------------
   --  Test configuration parameters --
   ------------------------------------

   File_Size   : Count   := 100_000;
   Continuous  : constant Boolean := False;

   Header      : constant ZLib.Header_Type := ZLib.Default;
                                              --  ZLib.None;
                                              --  ZLib.Auto;
                                              --  ZLib.GZip;
   --  Do not use Header other then Default in ZLib versions 1.1.4
   --  and older.

   Strategy    : constant ZLib.Strategy_Type := ZLib.Default_Strategy;
   Init_Random : constant := 10;

   -- End --

   In_File_Name  : constant String := "testzlib.in";
   --  Name of the input file

   Z_File_Name   : constant String := "testzlib.zlb";
   --  Name of the compressed file

   Out_File_Name : constant String := "testzlib.out";
   --  Name of the decompressed file

   File_In   : File_Type;
   File_Out  : File_Type;
   File_Back : File_Type;
   File_Z    : ZLib.Streams.Stream_Type;

   Filter    : ZLib.Filter_Type;

   procedure Generate_File;
   --  Generate file of spetsified size with some random data.
   --  The random data is repeatable, for the good compression.

   procedure Compare_Streams
     (Left, Right : in out Root_Stream_Type'Class);
   --  The procedure compearing data in 2 streams.
   --  It is for compare data before and after compression/decompression.

   procedure Compare_Files (Left, Right : String);
   --  Compare files. Based on the Compare_Streams

   procedure Copy_Streams
     (Source, Target : in out Root_Stream_Type'Class;
      Buffer_Size    : Stream_Element_Offset := 1024);
   --  Copying data from one stream to another. It is for test stream
   --  interface of the library.

   procedure Data_In
     (Item : out Stream_Element_Array;
      Last : out Stream_Element_Offset);
   --  this procedure is for generic instantiation of
   --  ZLib.Generic_Translate.
   --  reading data from the File_In.

   procedure Data_Out (Item : Stream_Element_Array);
   --  this procedure is for generic instantiation of
   --  ZLib.Generic_Translate.
   --  writing data to the File_Out.

   procedure Print_Statistic (Msg : String; Data_Size : ZLib.Count);
   --  Print the statistic with the message

   procedure Translate is
     new ZLib.Generic_Translate (Data_In => Data_In, Data_Out => Data_Out);
   --  This procedure is moving data from File_In to File_Out
   --  with compression or decompression, depend on initialization of
   --  Filter parameter.

   -------------------
   -- Compare_Files --
   -------------------

   procedure Compare_Files (Left, Right : String) is
      Left_File, Right_File : File_Type;
   begin
      Open (Left_File, In_File, Left);
      Open (Right_File, In_File, Right);
      Compare_Streams (Stream (Left_File).all, Stream (Right_File).all);
      Close (Left_File);
      Close (Right_File);
   end Compare_Files;

   ---------------------
   -- Compare_Streams --
   ---------------------

   procedure Compare_Streams
     (Left, Right : in out Streams.Root_Stream_Type'Class)
   is
      Left_Buffer, Right_Buffer : Stream_Element_Array (0 .. 16#FFF#);
      Left_Last, Right_Last     : Stream_Element_Offset;
   begin
      loop
         Read (Left, Left_Buffer, Left_Last);
         Read (Right, Right_Buffer, Right_Last);

         if Left_Last /= Right_Last then
            Text_IO.Put_Line ("Compare error :"
              & Stream_Element_Offset'Image (Left_Last)
              & " /= "
              & Stream_Element_Offset'Image (Right_Last));

            raise Constraint_Error;

         elsif Left_Buffer (0 .. Left_Last)
               /= Right_Buffer (0 .. Right_Last)
         then
            Text_IO.Put_Line ("ERROR: IN and OUT files is not equal.");
            raise Constraint_Error;

         end if;

         exit when Left_Last < Left_Buffer'Last;
      end loop;
   end Compare_Streams;

   ------------------
   -- Copy_Streams --
   ------------------

   procedure Copy_Streams
     (Source, Target : in out Streams.Root_Stream_Type'Class;
      Buffer_Size    : Stream_Element_Offset := 1024)
   is
      Buffer : Stream_Element_Array (1 .. Buffer_Size);
      Last   : Stream_Element_Offset;
   begin
      loop
         Read  (Source, Buffer, Last);
         Write (Target, Buffer (1 .. Last));

         exit when Last < Buffer'Last;
      end loop;
   end Copy_Streams;

   -------------
   -- Data_In --
   -------------

   procedure Data_In
     (Item : out Stream_Element_Array;
      Last : out Stream_Element_Offset) is
   begin
      Read (File_In, Item, Last);
   end Data_In;

   --------------
   -- Data_Out --
   --------------

   procedure Data_Out (Item : Stream_Element_Array) is
   begin
      Write (File_Out, Item);
   end Data_Out;

   -------------------
   -- Generate_File --
   -------------------

   procedure Generate_File is
      subtype Visible_Symbols is Stream_Element range 16#20# .. 16#7E#;

      package Random_Elements is
         new Numerics.Discrete_Random (Visible_Symbols);

      Gen    : Random_Elements.Generator;
      Buffer : Stream_Element_Array := (1 .. 77 => 16#20#) & 10;

      Buffer_Count : constant Count := File_Size / Buffer'Length;
      --  Number of same buffers in the packet

      Density : constant Count := 30; --  from 0 to Buffer'Length - 2;

      procedure Fill_Buffer (J, D : Count);
      --  Change the part of the buffer

      -----------------
      -- Fill_Buffer --
      -----------------

      procedure Fill_Buffer (J, D : Count) is
      begin
         for K in 0 .. D loop
            Buffer
              (Buffer'First + Stream_Element_Offset
                 ((J + K) mod (Buffer'Length - 1) + 1) - 1) :=
              Random_Elements.Random (Gen);
         end loop;
      end Fill_Buffer;

   begin
      Random_Elements.Reset (Gen, Init_Random);

      Create (File_In, Out_File, In_File_Name);

      Fill_Buffer (1, Buffer'Length - 2);

      for J in 1 .. Buffer_Count loop
         Write (File_In, Buffer);

         Fill_Buffer (J, Density);
      end loop;

      --  Fill remain size

      Write
        (File_In,
         Buffer
           (Buffer'First .. Buffer'First +
              Stream_Element_Offset
                (File_Size - Buffer'Length * Buffer_Count) - 1));

      Flush (File_In);
      Close (File_In);
   end Generate_File;

   ---------------------
   -- Print_Statistic --
   ---------------------

   procedure Print_Statistic (Msg : String; Data_Size : ZLib.Count) is
      package Count_IO is new Text_IO.Integer_IO (ZLib.Count);
   begin
      Text_IO.Put (Msg);

      Text_IO.Set_Col (20);
      Text_IO.Put ("size =");

      Count_IO.Put
        (Data_Size,
         Width => Stream_IO.Count'Image (File_Size)'Length);
      Text_IO.New_Line;
   end Print_Statistic;

   Z_Version : constant String := Zlib.Version;

begin
   Text_IO.Put_Line
     ("ZLib " & Z_Version (Z_Version'First .. Z_Version'First + 2));

   loop
      Generate_File;

      for Level in ZLib.Compression_Level'Range loop

         Text_IO.Put_Line ("Level ="
            & ZLib.Compression_Level'Image (Level));

         --  Test generic interface

         Open   (File_In, In_File, In_File_Name);
         Create (File_Out, Out_File, Z_File_Name);

         --  Deflate using generic instantiation

         ZLib.Deflate_Init
               (Filter   => Filter,
                Level    => Level,
                Strategy => Strategy,
                Header   => Header);

         Translate (Filter);
         Print_Statistic ("Generic compress", ZLib.Total_Out (Filter));
         ZLib.Close (Filter);

         Close (File_In);
         Close (File_Out);

         Open   (File_In, In_File, Z_File_Name);
         Create (File_Out, Out_File, Out_File_Name);

         --  Inflate using generic instantiation

         ZLib.Inflate_Init (Filter, Header => Header);

         Translate (Filter);
         Print_Statistic ("Generic decompress", ZLib.Total_Out (Filter));

         ZLib.Close (Filter);

         Close (File_In);
         Close (File_Out);

         Compare_Files (In_File_Name, Out_File_Name);

         --  Test stream interface

         --  Compress to the back stream

         Open   (File_In, In_File, In_File_Name);
         Create (File_Back, Out_File, Z_File_Name);

         ZLib.Streams.Create
           (Stream          => File_Z,
            Mode            => ZLib.Streams.Out_Stream,
            Back            => ZLib.Streams.Stream_Access
                                 (Stream (File_Back)),
            Back_Compressed => True,
            Level           => Level,
            Strategy        => Strategy,
            Header          => Header);

         Copy_Streams
           (Source => Stream (File_In).all,
            Target => File_Z);

         --  Flushing internal buffers to the back stream

         ZLib.Streams.Flush (File_Z, ZLib.Finish);

         Print_Statistic ("Write compress",
                          ZLib.Streams.Write_Total_Out (File_Z));

         ZLib.Streams.Close (File_Z);

         Close (File_In);
         Close (File_Back);

         --  Compare reading from original file and from
         --  decompression stream.

         Open (File_In,   In_File, In_File_Name);
         Open (File_Back, In_File, Z_File_Name);

         ZLib.Streams.Create
           (Stream          => File_Z,
            Mode            => ZLib.Streams.In_Stream,
            Back            => ZLib.Streams.Stream_Access
                                 (Stream (File_Back)),
            Back_Compressed => True,
            Header          => Header);

         Compare_Streams (Stream (File_In).all, File_Z);

         Print_Statistic ("Read decompress",
                          ZLib.Streams.Read_Total_Out (File_Z));

         ZLib.Streams.Close (File_Z);
         Close (File_In);
         Close (File_Back);

         --  Compress by reading from compression stream

         Open (File_Back, In_File, In_File_Name);
         Create (File_Out, Out_File, Z_File_Name);

         ZLib.Streams.Create
           (Stream          => File_Z,
            Mode            => ZLib.Streams.In_Stream,
            Back            => ZLib.Streams.Stream_Access
                                 (Stream (File_Back)),
            Back_Compressed => False,
            Level           => Level,
            Strategy        => Strategy,
            Header          => Header);

         Copy_Streams
           (Source => File_Z,
            Target => Stream (File_Out).all);

         Print_Statistic ("Read compress",
                          ZLib.Streams.Read_Total_Out (File_Z));

         ZLib.Streams.Close (File_Z);

         Close (File_Out);
         Close (File_Back);

         --  Decompress to decompression stream

         Open   (File_In,   In_File, Z_File_Name);
         Create (File_Back, Out_File, Out_File_Name);

         ZLib.Streams.Create
           (Stream          => File_Z,
            Mode            => ZLib.Streams.Out_Stream,
            Back            => ZLib.Streams.Stream_Access
                                 (Stream (File_Back)),
            Back_Compressed => False,
            Header          => Header);

         Copy_Streams
           (Source => Stream (File_In).all,
            Target => File_Z);

         Print_Statistic ("Write decompress",
                          ZLib.Streams.Write_Total_Out (File_Z));

         ZLib.Streams.Close (File_Z);
         Close (File_In);
         Close (File_Back);

         Compare_Files (In_File_Name, Out_File_Name);
      end loop;

      Text_IO.Put_Line (Count'Image (File_Size) & " Ok.");

      exit when not Continuous;

      File_Size := File_Size + 1;
   end loop;
end Test_Zlib;
