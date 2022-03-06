with AAA.Filesystem;
with AAA.Strings;
with AAA.Text_IO;

with Ada.Text_IO;

package body TOML_Slicer is

   Debug : constant Boolean := False;

   ---------------
   -- Debug_Put --
   ---------------

   procedure Put_Debug (Line : String) is
   begin
      if Debug then
         Ada.Text_IO.Put_Line ("[TOML_Slicer debug] " & Line);
      end if;
   end Put_Debug;

   ------------------
   -- Remove_Array --
   ------------------

   procedure Remove_Array (File_Name  : String;
                           Array_Name : String;
                           Backup     : Boolean;
                           Backup_Dir : String := ".")
   is

      ------------
      -- Remove --
      ------------

      procedure Remove (Lines : in out AAA.Strings.Vector) is
         use AAA.Strings;

         Starter_1 : constant String := "[[" & Array_Name & "]]";
         Starter_2 : constant String := "[[" & Array_Name & ".";
         Starter_3 : constant String := "[" & Array_Name & ".";

         ------------------
         -- Out_Of_Array --
         ------------------

         function Out_Of_Array (Line : String) return Boolean is
         begin
            --  Check this is a simple nested table field or empty line
            if Line'Length = 0 or else Line (Line'First) /= '[' then
               return False;
            end if;

            --  Otherwise, check we're not entering a different array
            if Has_Prefix (Line, Starter_1) or else
              Has_Prefix (Line, Starter_2) or else
              Has_Prefix (Line, Starter_3)
            then
               --  Still fields/entries of the same array,
               --  either a subtable or a nested array. See
               --  https://toml.io/en/v1.0.0#array-of-tables
               return False;
            else
               return True;
            end if;
         end Out_Of_Array;

         Armed     : Boolean := False;
         --  True when we are inside [[array]]

         I : Positive := 1;
      begin
         while I <= Lines.Last_Index loop
            declare
               Line  : constant String := Replace (Lines (I), " ", "");
            begin
               if Armed then
                  if not Out_Of_Array (Line) then
                     Put_Debug ("DELETE: " & Line);
                     Lines.Delete (I);
                  else
                     Put_Debug ("DISARM: " & Line);
                     Armed := False;
                     I := I + 1;
                  end if;
               else -- not armed
                  if Has_Prefix (Line, Starter_1) or else
                    Has_Prefix (Line, Starter_2)
                    --  Starter_3 would be a nested table but not array
                  then
                     Put_Debug ("ARMED: " & Line);
                     Armed := True;
                     Lines.Delete (I);
                  else
                     Put_Debug ("NOT ARM: " & Line);
                     I := I + 1;
                  end if;
               end if;
            end;
         end loop;
      end Remove;

      Replacer  : constant AAA.Filesystem.Replacer :=
                    AAA.Filesystem.New_Replacement
                      (File_Name,
                       Backup     => Backup,
                       Backup_Dir => Backup_Dir);
   begin
      declare
         File      : constant AAA.Text_IO.File :=
                       AAA.Text_IO.Load (Replacer.Editable_Name,
                                         Backup => False);
         --  Replacer takes care of backup
      begin
         Remove (File.Lines.all);
      end;
      --  File goes out of scope here and rewrites the contents, so the
      --  replacer keeps the already modified file.

      Replacer.Replace; -- All went well, keep the changes
   end Remove_Array;

   ----------------------------
   -- Remove_Line_From_Array --
   ----------------------------

   procedure Remove_Line_From_Array (File_Name  : String;
                                     Array_Name : String;
                                     Entry_Name : String;
                                     Cleanup    : Boolean;
                                     Backup     : Boolean;
                                     Backup_Dir : String := ".")
   is

      ------------
      -- Remove --
      ------------

      procedure Remove (Lines : in out AAA.Strings.Vector)
      --  Remove Entry_Name from Lines
      is
         Enter_Marker : constant String := "[[" & Array_Name & "]]";
         --  We must see a line like this before being able to remove a dep.

         Target       : constant String := Entry_Name & "=";
         --  A line starting with Target is a candidate for deletion

         Armed        : Boolean := False;
         --  True when we are inside [[array]]

         Found        : Boolean := False; -- True when the entry was found

         -------------------
         -- Remove_Target --
         -------------------

         procedure Remove_Target is
            use AAA.Strings;
         begin
            for I in Lines.First_Index .. Lines.Last_Index loop
               declare
                  Line  : constant String := Replace (Lines (I), " ", "");
               begin

                  if Armed and then Has_Prefix (Line, Target) then
                     Found := True;
                     Lines.Delete (I);
                     exit;

                  elsif Has_Prefix (Line, "[[") then
                     --  Detect a plain [[array]] with optional comment
                     Armed :=
                       Line = Enter_Marker or else
                       Has_Prefix (Line, Enter_Marker & '#');

                  elsif Armed and then Line /= "" and then
                    Line (Line'First) /= '[' -- not a table or different array
                  then
                     --  We are seeing a different entry in the same array
                     --  entry; we can still remove our target if later found
                     --  in this entry.
                     null;

                  elsif Line = "" or else Has_Prefix (Line, "#") then
                     --  We still can remove an entry found in this array entry
                     null;

                  else
                     --  Any other sighting complicates matters and we won't
                     --  touch it.
                     Armed := False;

                     --  TODO: be able to remove a table in the array named as
                     --  Entry, i.e., something like:
                     --  [[array]]
                     --  [array.entry] or [array.entry.etc]
                     --  etc

                     --  Or, be able to remove something like
                     --  [[array]]
                     --  entry.field = ...
                  end if;
               end;
            end loop;

            if not Found then
               raise Slicing_Error with
                 "Could not find removable entry " & Entry_Name
                 & " in array " & Array_Name & " in file " & File_Name;
               return;
            end if;
         end Remove_Target;

         -------------------------
         -- Remove_Empty_Arrays --
         -------------------------

         procedure Remove_Empty_Arrays is
            --  This might probably be done with multiline regular expressions

            Deletable : Natural := 0;
            --  Tracks how many empty lines we have seen since the last [[

            Can_Delete : Boolean := True;
            --  We can delete as long as we are only seeing empty lines

            use AAA.Strings;
         begin

            --  Traverse lines backwards

            for I in reverse Lines.First_Index .. Lines.Last_Index loop
               declare
                  Line : constant String := Replace (Lines (I), " ", "");
               begin
                  if Can_Delete then
                     --  Look for empty lines or the opening [[array]]
                     if Line = "" then
                        Deletable := Deletable + 1;

                     elsif
                       Line = Enter_Marker or else
                       Has_Prefix (Line, Enter_Marker & '#')
                     then
                        --  Now we can delete the empty [[array]] plus any
                        --  following empty lines.
                        for J in 0 .. Deletable loop -- 0 for the current line
                           Lines.Delete (I);
                        end loop;

                        --  Restart, we can still delete previous entries
                        Deletable := 0;

                     else
                        --  We found something else, so do not remove entry
                        Can_Delete := False;
                        Deletable  := 0;
                     end if;

                  else
                     --  Look for a [[ that starts another array entry. We
                     --  cannot rely on simply [ for tables, these could be
                     --  nested array tables.
                     if Has_Prefix (Line, "[[") then
                        Can_Delete := True;
                        Deletable  := 0;
                        --  We will look in next iterations for a precedent
                        --  empty array entry.
                     end if;
                  end if;
               end;
            end loop;
         end Remove_Empty_Arrays;

      begin

         --  First pass, remove a detected entries in the proper location.
         --  Note that this only removes the entry line, but not the enclosing
         --  [[array]]. It is ok to have such an empty array entry. Empty array
         --  entries are cleaned up afterwards.

         Remove_Target;

         --  Second pass, remove empty [[array]] array entries. This ensures
         --  that trivial add/remove of array entries cannot grow the file
         --  indefinitely with empty [[]] entries.

         if Cleanup then
            Remove_Empty_Arrays;
         end if;

      end Remove;

      Replacer : constant AAA.Filesystem.Replacer :=
                   AAA.Filesystem.New_Replacement
                     (File_Name,
                      Backup     => Backup,
                      Backup_Dir => Backup_Dir);
   begin

      declare
         File : constant AAA.Text_IO.File :=
                  AAA.Text_IO.Load (Replacer.Editable_Name,
                                    Backup => False);
                                    --  Replacer takes care of backup
      begin
         Remove (File.Lines.all);
      end;

      Replacer.Replace; -- All went well, keep the changes
   end Remove_Line_From_Array;

end TOML_Slicer;
