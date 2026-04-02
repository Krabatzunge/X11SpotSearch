const std = @import("std");

pub const Icons = enum {
    Browser,
    DefaultApplication,

    const browser = @embedFile("./assets/icons/browser.svg");
    const browserId = "icons.browser";
    const default_application = @embedFile("./assets/icons/default-application.svg");
    const default_applicationId = "icons.default_application";

    pub fn getData(icon: Icons) []const u8 {
        switch (icon) {
            Icons.Browser => return browser,
            Icons.DefaultApplication => return default_application,
        }
    }

    pub fn toId(icon: Icons) []const u8 {
        switch (icon) {
            Icons.Browser => return browserId,
            Icons.DefaultApplication => return default_applicationId,
        }
    }

    pub fn fromId(id: []const u8) ?Icons {
        if (std.mem.eql(u8, id, browserId)) {
            return Icons.Browser;
        } else if (std.mem.eql(u8, id, default_applicationId)) {
            return Icons.DefaultApplication;
        }
        return null;
    }
};
