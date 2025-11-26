const std = @import("std");

pub const FileReader = struct {
    file: std.fs.File,
    buffer: [4096]u8,
    buffer_pos: usize,
    buffer_len: usize,
    
    pub fn init(path: []const u8) !FileReader {
        const file = try std.fs.cwd().openFile(path, .{});
        return FileReader{
            .file = file,
            .buffer = undefined,
            .buffer_pos = 0,
            .buffer_len = 0,
        };
    }
    
    pub fn deinit(self: *FileReader) void {
        self.file.close();
    }
    
    pub fn read_in_char(self: *FileReader) ?u8 {
        // Refill buffer if empty
        if (self.buffer_pos >= self.buffer_len) {
            self.buffer_len = self.file.read(&self.buffer) catch return null;
            if (self.buffer_len == 0) return null;
            self.buffer_pos = 0;
        }
        
        const char = self.buffer[self.buffer_pos];
        self.buffer_pos += 1;
        return char;
    }
};
