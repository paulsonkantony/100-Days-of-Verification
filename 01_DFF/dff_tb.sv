class transaction;
  
  //All signals excluding global signals
  randc bit [7:0] din;
  bit [7:0] dout;
  
  //Deep Copy
  function transaction copy();
    copy = new();
    copy.din = this.din;
    copy.dout = this.dout;
  endfunction
  
  function void display(input string tag);
    $display("[%0t] : [%0s] : Data in : %0d : Data Out : %0d", $realtime(), tag, din, dout);
  endfunction

endclass
  
class dff_model;
  
  bit [7:0] din = 8'h00;
  bit [7:0] dout = 8'h00; 
  
  function void update(bit [7:0] data);
    din = data;
    dout = data;
  endfunction
  
  function void reset();
    din = 8'h00;
    dout = 8'h00;
  endfunction

  function transaction get_tr();
    transaction tr = new();
    tr.din = this.din;
    tr.dout = this.dout;
    return tr;
  endfunction
  
endclass

class generator;

    transaction tr;
    dff_model dff_ref;

    mailbox #(transaction) mbx; //Send data to driver
    mailbox #(dff_model) mbxref; //Send reference object to scoreboard

    event sconext; //Scoreboard Iteration completed
    event done; //Requested number of stimulus sent

    int count; //Requested number of stimulus

    function new(mailbox #(transaction) mbx, mailbox #(dff_model) mbxref);
        this.mbx = mbx;
        this.mbxref = mbxref;
        tr = new();
        dff_ref = new();
    endfunction

    task run();
        repeat(count) begin //Repeat until requested number of stimulus done
            assert(tr.randomize()) else $error("[GEN] Randomization Failed");
            tr.display("GEN");
            mbx.put(tr.copy());
            dff_ref.update(tr.din);
            mbxref.put(dff_ref);
            @(sconext);
        end
        ->done;
    endtask

endclass

class driver;

    virtual dff_if vif;
    //Virtual Interface is needed because classes are dynamic objects and interfaces are static objects
    //In OOP, we cannot refer static objects from dynamic objects
    transaction tr;
    mailbox #(transaction) mbx; //Storing data from generator
    event monitor_sample; //Sync with monitor

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task reset;
        vif.rst <= 1'b0;
        repeat(5) @(posedge vif.clk);
        vif.rst <= 1'b1;
        @(posedge vif.clk);
        $display("[%0t] : [DRV] : Reset Successful", $realtime());
    endtask

    task run();
        forever begin
            mbx.get(tr);
            vif.din <= tr.din; //Non Blocking because procedural block
            @(posedge vif.clk);
            tr.display("DRV");
            ->monitor_sample;
            vif.din <= 8'h00;
            @(posedge vif.clk);
        end
    endtask

endclass

class monitor;

    transaction tr;
    mailbox #(transaction) mbx;
    virtual dff_if vif;
    event monitor_sample;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task run();
        tr = new();
        forever begin
            @(monitor_sample);
            //@(posedge vif.clk);
            //Non Blocking Assignment simply calculates the RHS at the beginning of the procedural block
            //https://electronics.stackexchange.com/questions/583402/why-does-non-blocking-assignment-in-verilog-seem-like-a-misnomer
            tr.din = vif.din;
            @(posedge vif.clk);
            tr.dout = vif.dout;
            mbx.put(tr);
            tr.display("MON");
        end
    endtask

endclass

class scoreboard;

    transaction tr;
    dff_model dff_ref;

    mailbox #(transaction) mbx;
    mailbox #(dff_model) mbxref;

    event sconext;
    event done;

    int count;

    function new(mailbox #(transaction) mbx, mailbox #(dff_model) mbxref);
        this.mbx = mbx;
        this.mbxref = mbxref;
    endfunction

    task run();
        forever begin
            mbx.get(tr);
            mbxref.get(dff_ref);
            tr.display("SCO");
            dff_ref.get_tr().display("REF");
            if(tr.dout == dff_ref.dout) $display("[%0t] : [SCO] : DATA MATCH", $realtime());
            else $error("[SCO] : DATA MISMATCH");
            $display("-----------------------------");
            ->sconext;
        end
    endtask

endclass

class environment;

    virtual dff_if vif;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;

    event next;
    event monitor_sample;

    mailbox #(transaction) gdmbx, msmbx;
    mailbox #(dff_model) mbxref;

    function new(virtual dff_if vif);
        gdmbx = new();
        msmbx = new();
        mbxref = new();

        gen = new(gdmbx, mbxref);
        drv = new(gdmbx);
        mon = new(msmbx);
        sco = new(msmbx, mbxref);

        this.vif = vif;
        drv.vif = this.vif;
        mon.vif = this.vif;

        gen.sconext = next;
        sco.sconext = next;

        drv.monitor_sample = this.monitor_sample;
        mon.monitor_sample = this.monitor_sample;

    endfunction

    task pre_test();
        drv.reset();
    endtask

    task post_test();
        wait(gen.done.triggered);
        $finish();
    endtask

    task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            sco.run();
        join_any
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask

endclass


module tb;
  
  dff_if vif();
  environment env;
  
  initial begin
    vif.clk <= 1'b0;
    vif.rst <= 1'b1;
  end

  always #10 vif.clk <= ~vif.clk;

  dff dut(
    .clk(vif.clk),
    .rst(vif.rst),
    .din(vif.din),
    .dout(vif.dout)
    );

  initial begin
    env = new(vif);
    env.gen.count = 30;
    env.run();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
    
endmodule
