const std = @import("std");

// State to track file reading
const FileReader = struct {
    file: std.fs.File,
    buffered: std.io.BufferedReader(4096, std.fs.File.Reader),
    
    pub fn init(path: []const u8) !FileReader {
        const file = try std.fs.cwd().openFile(path, .{});
        const buffered = std.io.bufferedReader(file.reader());
        return FileReader{
            .file = file,
            .buffered = buffered,
        };
    }
    
    pub fn deinit(self: *FileReader) void {
        self.file.close();
    }
    
    pub fn read_in_char(self: *FileReader) ?u8 {
        return self.buffered.reader().readByte() catch null;
    }
};
