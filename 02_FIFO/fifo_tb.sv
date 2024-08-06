class transaction;

    //Everything except global signals + Operation bit to indicate read/write

    rand bit en;
    rand bit push_in, pop_in;
    randc bit [7:0] din;
    bit [3:0] threshold = 10;
    bit [7:0] dout;
    bit empty, full, overrun, underrun, threshold_trigger;

    constraint en_ctrl {
        en dist {1:/90, 0:/10};
    }
    constraint push_pop_ctrl {
        {push_in, pop_in} dist {
            2'b00 := 10,
            2'b01 := 40,
            2'b10 := 40,
            2'b11 := 10
        };
    }

    function void display(input string tag);
        $display("[%0t] : [%0s] : en : %0d :: push_in : %0d :: pop_in : %0d :: din : %0d :: threshold : %0d :: dout : %0d :: empty : %0d :: full : %0d :: overrun : %0d :: underrun : %0d :: threshold_trigger : %0d",
        $realtime(), tag, en, push_in, pop_in, din, threshold, dout, empty, full, overrun, underrun, threshold_trigger);
    endfunction

    function transaction copy();

        copy = new();
        copy.en = this.en;
        copy.push_in = this.push_in;
        copy.pop_in = this.pop_in;
        copy.din = this.din;
        copy.threshold = this.threshold;
        copy.dout = this.dout;
        copy.empty = this.empty;
        copy.full = this.full;
        copy.overrun = this.overrun;
        copy.underrun = this.underrun;
        copy.threshold_trigger = this.threshold_trigger;
    
    endfunction

endclass

class fifo_model;

    bit [3:0] threshold = 10;
    bit [4:0] depth = 16; //Gives 0 if saved in [3:0]
    bit [7:0] mem[$]; // Queue - Golden Data
    bit [7:0] dout;
    bit empty = 1, full = 0, overrun = 0, underrun = 0, threshold_trigger = 0;

    function void push(bit [7:0] data);
        if(full) begin
            overrun = 1;
            underrun = 0;
        end
        else begin
            underrun = 0;
            overrun = 0;
            mem.push_back(data);
            dout = mem[0];
            threshold_logic();
            threshold_logic();
            empty_logic();
            full_logic();           
        end
    endfunction

    function bit [7:0] pop();
        
        logic [7:0] temp; //Temp has to be declared in the beginning or else ERROR
        if(empty) begin
            overrun = 0;
            underrun = 1;
            return 8'h00;
        end
        else begin
            underrun = 0;
            overrun = 0;
            temp = mem.pop_front();
            if(mem.size == 0) dout = 8'h00;
            else dout = mem[0];
            threshold_logic();
            empty_logic();
            full_logic();
            return temp;
        end
    endfunction

    function void threshold_logic();
        if(mem.size() == threshold) threshold_trigger = 1;
        else threshold_trigger = 0;
    endfunction

    function void empty_logic();
        if(mem.size() == 0) empty = 1;
        else empty = 0;
    endfunction

    function void full_logic();
        if(mem.size() == 0) full = 1;
        else full = 0;
    endfunction

    function transaction get_tr();
        
        get_tr = new();
        get_tr.en = 1'bx;
        get_tr.push_in = 1'bx;
        get_tr.pop_in = 1'bx;
        get_tr.din = 8'hxx;
        get_tr.threshold = this.threshold;
        get_tr.dout = this.dout;
        get_tr.empty = this.empty;
        get_tr.full = this.full;
        get_tr.overrun = this.overrun;
        get_tr.underrun = this.underrun;
        get_tr.threshold_trigger = this.threshold_trigger;

    endfunction

endclass


class generator;

    transaction tr;
    fifo_model fifo_ref; 
    mailbox #(transaction) mbx;
    mailbox #(fifo_model) mbxref;

    int count = 0; //Number of transactions to generate
    int i = 0; //Current Iteration Count

    event sconext; //Send next transaction
    event done; //Requested number of stimuli generated

    function new(mailbox #(transaction) mbx, mailbox #(fifo_model) mbxref);
        this.mbx = mbx;
        this.mbxref = mbxref;
        tr = new();
        fifo_ref = new();
    endfunction

    task run();
        repeat(count) begin
            assert(tr.randomize()) else $error("[%0t] : [GEN] : RANDOMIZATION FAILED", $realtime());
            ++i;
            mbx.put(tr.copy);
            
            if(tr.en) begin
                case({tr.push_in, tr.pop_in})
                    2'b01: fifo_ref.pop();
                    2'b10: fifo_ref.push(tr.din);
                endcase
            end
            mbxref.put(fifo_ref);

            $display("[%0t] : [GEN] : Iteration : %0d", $realtime(), i);
            tr.display("GEN");
            @(sconext);
        end
        ->done;
    endtask

endclass

class driver;

    virtual fifo_if vif;
    //Virtual Interface is needed because classes are dynamic objects and interfaces are static objects
    //In OOP, we cannot refer static objects from dynamic objects
    transaction tr;
    mailbox #(transaction) mbx; //Storing data from generator
    event monitor_sample;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task reset();
        vif.rst <= 1'b1;
        repeat(5) @(posedge vif.clk); //Wait for 5 cycles
        vif.rst <= 1'b0;
        @(posedge vif.clk);
        $display("[DRV] : RESET SUCCESSFUL");
    endtask

    task run();

        forever begin
            mbx.get(tr);

            vif.en <= tr.en;
            vif.push_in <= tr.push_in;
            vif.pop_in <= tr.pop_in;
            vif.din <= tr.din;
            
            @(posedge vif.clk);

            ->monitor_sample;
            tr.display("DRV");

            vif.en <= tr.en;
            vif.push_in <= 0;
            vif.pop_in <= 0;
            vif.din <= 0;
            
            @(posedge vif.clk);
          
        end
    
    endtask

endclass

class monitor;

    virtual fifo_if vif;
    mailbox #(transaction) mbx;
    transaction tr;
    event monitor_sample;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task run();

        tr = new();

        forever begin
            //repeat(2) 
            @(monitor_sample);
            //Wait for the 2 clock cycles in Read/Write at the time after input is done
            tr.en = vif.en;
            tr.push_in = vif.push_in;
            tr.pop_in = vif.pop_in;
            tr.din = vif.din;
            tr.threshold = vif.threshold;
            @(posedge vif.clk);
            tr.dout = vif.dout;
            tr.empty = vif.empty;
            tr.full = vif.full;
            tr.overrun = vif.overrun;
            tr.underrun = vif.underrun;
            tr.threshold_trigger = vif.threshold_trigger;

            mbx.put(tr);
            tr.display("MON");
        end

    endtask
endclass

class scoreboard;

    transaction tr;
    fifo_model fifo_ref;
    
    mailbox #(transaction) mbx;
    mailbox #(fifo_model) mbxref;

    event sconext;
    event done;

    int count;
    int err = 0;

    function new(mailbox #(transaction) mbx, mailbox #(fifo_model) mbxref);
        this.mbx = mbx;
        this.mbxref = mbxref;
    endfunction

    task run();

        forever begin

            mbx.get(tr);
            mbxref.get(fifo_ref);

            tr.display("SCO");
            fifo_ref.get_tr().display("REF");

            if(tr.dout == fifo_ref.dout) $display("[%0t] : [SCO] : DATA MATCH", $realtime());
            else begin
                ++err;
                $error("[%0t] : [SCO] : DATA MISMATCH", $realtime());
            end
            $display("---------------------------------------");
            ->sconext;
        end

    endtask

endclass


class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;

    mailbox #(transaction) gdmbx;
    mailbox #(transaction) msmbx;
    mailbox #(fifo_model) mbxref;

    event nextgs;
    event monitor_sample;

    virtual fifo_if fif;

    function new(virtual fifo_if fif);

        gdmbx = new();
        msmbx = new();
        mbxref = new();

        gen = new(gdmbx, mbxref);
        drv = new(gdmbx);
        mon = new(msmbx);
        sco = new(msmbx, mbxref);

        this.fif = fif;
        drv.vif = this.fif;
        mon.vif = this.fif;

        gen.sconext = nextgs;
        sco.sconext = nextgs;
        drv.monitor_sample = this.monitor_sample;
        mon.monitor_sample = this.monitor_sample;

    endfunction

    task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
    endtask

    task post_test();
        wait(gen.done.triggered);
        $display("[%0t] : [ENV] : Simulation finished.", $realtime());
        $display("---------------------------------------");
        $display("[%0t] : [ENV] : Number of errors : %0d", $realtime(), sco.err);
        $display("---------------------------------------");
        $finish();
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask

endclass

module tb;

    fifo_if fif();

    fifo dut(.clk(fif.clk), .rst(fif.rst), .en(fif.en),
             .push_in(fif.push_in), .pop_in(fif.pop_in), 
             .din(fif.din), .threshold(fif.threshold), .dout(fif.dout),
             .empty(fif.empty), .full(fif.full),
             .overrun(fif.overrun), .underrun(fif.underrun),
             .threshold_trigger(fif.threshold_trigger)
             );

    initial begin
        fif.clk <= 0;
        fif.threshold <= 10;
    end
    always #10 fif.clk <= ~fif.clk;

    environment env;

    initial begin
        env = new(fif);
        env.gen.count = 100;
        env.run();
    end

    initial begin
        $dumpfile("var.vcd");
        $dumpvars;
    end

endmodule

