const std = @import("std");

pub const EvalError = error{
    InvalidCharacter,
    UnexpectedEnd,
    DivisionByZero,
    InvalidExpression,
    InvalidNumber,
    Overflow,
};

const Parser = struct {
    input: []const u8,
    pos: usize = 0,

    fn peek(self: *Parser) ?u8 {
        if (self.pos < self.input.len) return self.input[self.pos];
        return null;
    }

    fn consume(self: *Parser) u8 {
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }
    }

    fn parseNumber(self: *Parser) EvalError!f64 {
        self.skipWhitespace();
        const start = self.pos;
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
            self.pos += 1;
        }
        if (self.pos == start) return EvalError.UnexpectedEnd;
        return std.fmt.parseFloat(f64, self.input[start..self.pos]) catch EvalError.InvalidNumber;
    }

    fn parseFactor(self: *Parser) EvalError!f64 {
        self.skipWhitespace();
        const c = self.peek() orelse return EvalError.UnexpectedEnd;

        if (std.ascii.isDigit(c)) {
            return self.parseNumber();
        } else if (c == '(') {
            _ = self.consume(); // '('
            const val = try self.parseExpr();
            self.skipWhitespace();
            if (self.peek() != ')') return EvalError.InvalidExpression;
            _ = self.consume(); // ')'
            return val;
        } else {
            return EvalError.InvalidCharacter;
        }
    }

    fn parseTerm(self: *Parser) EvalError!f64 {
        var left = try self.parseFactor();
        while (true) {
            self.skipWhitespace();
            const op = self.peek() orelse return left;
            if (op == '*' or op == '/') {
                _ = self.consume();
                const right = try self.parseFactor();
                if (op == '*') {
                    left = left * right;
                } else {
                    if (right == 0) return EvalError.DivisionByZero;
                    left = left / right; // Integer division (truncates toward 0)
                }
            } else return left;
        }
    }

    fn parseExpr(self: *Parser) EvalError!f64 {
        var left = try self.parseTerm();
        while (true) {
            self.skipWhitespace();
            const op = self.peek() orelse return left;
            if (op == '+' or op == '-') {
                _ = self.consume();
                const right = try self.parseTerm();
                left = if (op == '+') left + right else left - right;
            } else return left;
        }
    }
};

pub fn evaluate(expr: []const u8) EvalError!f64 {
    var parser = Parser{ .input = expr };
    const result = try parser.parseExpr();
    parser.skipWhitespace();
    if (parser.pos < expr.len) return EvalError.InvalidExpression; // Trailing garbage
    return result;
}
