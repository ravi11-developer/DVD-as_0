`timescale 1ns/1ps

module tb_mult;
    reg clk;
    reg rst_n;
    reg [3:0] a;
    reg [3:0] b;
    wire [7:0] p;
    integer i, j, errors;
    reg [7:0] expected;

    mult_array uut (.clk(clk), .rst_n(rst_n), .a(a), .b(b), .p(p));

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("mult.vcd");
        $dumpvars(0, tb_mult);
        errors = 0; rst_n = 0; a = 0; b = 0;
        
        @(posedge clk); @(posedge clk);
        rst_n = 1;
        
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                @(posedge clk);
                a <= i; 
                b <= j; 
                expected = i * j;
                @(posedge clk); 
                @(posedge clk); 
                #1; 
                if (p !== expected) begin
                    $display("Mismatch: a=%d b=%d expected=%d got=%d", a, b, expected, p);
                    errors = errors + 1;
                end
            end
        end
        if (errors == 0) $display("PASS: 256 vectors checked, 0 errors");
        else $display("FAIL: 256 vectors checked, %d errors", errors);
        $finish;
    end
endmodule