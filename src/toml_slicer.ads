package TOML_Slicer is

   --  Procedures to directly edit a TOML file without parsing it. Heavily
   --  incomplete and tailored to Alire needs.

   Slicing_Error : exception;
   --  Raised when the requested operation could not be completed. Original
   --  file remains untouched.

   procedure Remove_Line_From_Array (File_Name  : String;
                                     Array_Name : String;
                                     Entry_Name : String;
                                     Cleanup    : Boolean;
                                     Backup     : Boolean;
                                     Backup_Dir : String := ".");
   --  Removes a line starting with Entry_Name = ... from [[Array_Name]].
   --  If Cleanup, it will remove empty array entries (all of them). A
   --  "filename.prev" file will be copied into Backup_Dir with the
   --  original contents in case of success.

end TOML_Slicer;
