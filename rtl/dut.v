module RELU (
	input wire signed [15:0] unclipped,
	output reg [7:0] clipped
	);
	always @ (*) begin
		if (unclipped > 127)
			clipped = 127;
		else if (unclipped < 0)
			clipped = 0;
		else
			clipped = unclipped[7:0];
	end
endmodule

module MyDesign (
//---------------------------------------------------------------------------
//Control signals
  input   wire dut_run                    , 
  output  reg dut_busy                   ,
  input   wire reset_b                    ,  
  input   wire clk                        ,
 
//---------------------------------------------------------------------------
//Input SRAM interface
  output reg        input_sram_write_enable    ,
  output reg [11:0] input_sram_write_addresss  ,
  output reg [15:0] input_sram_write_data      ,
  output reg [11:0] input_sram_read_address    ,
  input wire [15:0] input_sram_read_data       ,

//---------------------------------------------------------------------------
//Output SRAM interface
  output reg        output_sram_write_enable    ,
  output reg [11:0] output_sram_write_addresss  ,
  output reg [15:0] output_sram_write_data      ,
  output reg [11:0] output_sram_read_address    ,
  input wire [15:0] output_sram_read_data       ,

//---------------------------------------------------------------------------
//Scratchpad SRAM interface
  output reg        scratchpad_sram_write_enable    ,
  output reg [11:0] scratchpad_sram_write_addresss  ,
  output reg [15:0] scratchpad_sram_write_data      ,
  output reg [11:0] scratchpad_sram_read_address    ,
  input wire [15:0] scratchpad_sram_read_data       ,

//---------------------------------------------------------------------------
//Weights SRAM interface                                                       
  output reg        weights_sram_write_enable    ,
  output reg [11:0] weights_sram_write_addresss  ,
  output reg [15:0] weights_sram_write_data      ,
  output reg [11:0] weights_sram_read_address    ,
  input wire [15:0] weights_sram_read_data       

);

  //YOUR CODE HERE
  // Reference Design = ECE 464\In Class Notes- 2022\conv_accum.v
  
  //Parameters
  localparam Reset		= 4'b0000;
  localparam Prep0		= 4'b0001;
  localparam Prep1		= 4'b0010;
  localparam S0			= 4'b0011;
  localparam S0_Init	= 4'b0100;
  localparam S1			= 4'b0101;
  localparam S2			= 4'b0110;
  localparam S3			= 4'b0111;
  localparam S4			= 4'b1000;
  localparam S5			= 4'b1001;
  localparam S6			= 4'b1010;
  localparam S7			= 4'b1011;

// Sequential Register Declaration
reg signed [15:0] C0, C1, C2, C3;
reg [3:0] state;
reg [7:0] K0, K1, K2, K3, K4, K5, K6, K7, K8;
// input_sram_read_address, output_sram_write_addresss, weights_sram_read_address - covered in the IO

// Combinational Logic Declaration
reg NewCol, DoneSig;	// Additional State Variables. Input_sram_read_address and output_sram_wrige_address are also used as a state variables
wire [2:0] inputCol;
wire [8:0] inputRow;
reg [7:0] I0, I1;
wire [7:0] RELU_C0, RELU_C1, RELU_C2, RELU_C3;
reg signed [15:0] P0, P01, P1, P2, P23, P3;
reg signed [7:0] M0A, M0B, M01A, M01B, M1A, M1B, M2A, M2B, M23A, M23B, M3A, M3B;
reg ResetC01, ResetC23;
reg signed [15:0] NextC0, NextC1, NextC2, NextC3;
reg RouteToC0, RouteToC2;

// Assign combinational logic signals / flags
assign inputCol = input_sram_read_address[2:0];		// Mod 8 to get col
assign inputRow = input_sram_read_address[11:3];	// Divide by 8 to get row

RELU Urelu0 ( .unclipped(C0), .clipped(RELU_C0) );
RELU Urelu1 ( .unclipped(C1), .clipped(RELU_C1) );
RELU Urelu2 ( .unclipped(C2), .clipped(RELU_C2) );
RELU Urelu3 ( .unclipped(C3), .clipped(RELU_C3) );

// Set constant values for some of the IO
always @ (*) begin
	input_sram_write_enable = 0;
	input_sram_write_addresss = 0;
	input_sram_write_data = 0;
	
	weights_sram_write_enable = 0;
	weights_sram_write_addresss = 0;
	weights_sram_write_data = 0;
	
	output_sram_read_address = 0;
	
	scratchpad_sram_write_enable = 0;
	scratchpad_sram_write_addresss = 0;
	scratchpad_sram_write_data = 0;
	scratchpad_sram_read_address = 0;
	
	if (state == Reset)
		dut_busy = 0;
	else
		dut_busy = 1;
end

// Datapath Combo Logic
// For the multiplyers
always @ (*) begin
	P0 = M0A * M0B;
	P01 = M01A * M01B;
	P1 = M1A * M1B;
	
	P2 = M2A * M2B;
	P23 = M23A * M23B;
	P3 = M3A * M3B;
	
	if (ResetC01) begin
		NextC0 = 0;
		NextC1 = 0;
	end
	else begin
		if (RouteToC0) begin
			NextC0 = C0 + P0 + P01;
			NextC1 = C1 + P1;
		end
		else begin
			NextC0 = C0 + P0;
			NextC1 = C1 + P1 + P01;
		end
	end
	
	if (ResetC23) begin
		NextC2 = 0;
		NextC3 = 0;
	end
	else begin
		if (RouteToC2) begin
			NextC2 = C2 + P2 + P23;
			NextC3 = C3 + P3;
		end
		else begin
			NextC2 = C2 + P2;
			NextC3 = C3 + P3 + P23;
		end
	end
end

// Output SRAM


// Datapath Sequential Logic Registers
// For C0 thru C3 (resetting and routing the right inputs to the multipliers)
// Registers
	// C0 thru C3 - 16 bits (needs to be more than 8 bits) for the overflow
always @(posedge clk) begin
	C0 <= NextC0;
	C1 <= NextC1;
	C2 <= NextC2;
	C3 <= NextC3;
end
// Controller Combinational Logic
// For resetting C0 thru C3 (the convolution sums)
always @ (*) begin
	casex (state)
		// Cover the reset and prep state
		Reset : begin
			ResetC01 = 1;
			ResetC23 = 1;
		end
		
		// Cover the S1 state where we reset C23
		S1 : begin
			ResetC01 = 0;
			ResetC23 = 1;
		end
		
		// Cover the S7 state where we reset C01
		S7 : begin
			ResetC01 = 1;
			ResetC23 = 0;
		end
		
		// Cover the states where we don't reset C0 thru C3
		default : begin
			ResetC01 = 0;
			ResetC23 = 0;
		end
	endcase
end
// Controller Combinational Logic
// For getting the right inputs to the multiplers M0 thru M3
always @ (*) begin
	casex (state)
		S0 : begin
			// C0 += I0 * K0 + I1 * K1
			// C1 += I1 * K0
			M0A = I0; 	M0B = K0;
			M01A = I1;	M01B = K1;
			M1A = I1;	M1B = K0;
			RouteToC0 = 1;
			
			M2A = 0;	M2B = 0;
			M23A = 0;	M23B = 0;
			M3A = 0;	M3B = 0;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 3;
			
			// Output
				output_sram_write_data = {RELU_C2,RELU_C3};
				output_sram_write_enable = 1;
		end
		
		S0_Init : begin
			// C0 += I0 * K0 + I1 * K1
			// C1 += I1 * K0
			M0A = I0; 	M0B = K0;
			M01A = I1;	M01B = K1;
			M1A = I1;	M1B = K0;
			RouteToC0 = 1;
			
			M2A = 0;	M2B = 0;
			M23A = 0;	M23B = 0;
			M3A = 0;	M3B = 0;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 3;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		
		S1 : begin
			// C0 += I0 * K2
			// C1 += I0 * K1 + I1 * K2
			M0A = I0; 	M0B = K2;
			M01A = I0;	M01B = K1;
			M1A = I1;	M1B = K2;
			RouteToC0 = 0;
			
			M2A = 0;	M2B = 0;
			M23A = 0;	M23B = 0;
			M3A = 0;	M3B = 0;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 4;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		
		S2 : begin
			// C0 += I0 * K3 + I1 * K4
			// C1 += I1 * K3
			M0A = I0; 	M0B = K3;
			M01A = I1;	M01B = K4;
			M1A = I1;	M1B = K3;
			RouteToC0 = 1;
			
			// C2 += I0 * K0 + I1 * K1
			// C3 += I1 * K0
			M2A = I0;	M2B = K0;
			M23A = I1;	M23B = K1;
			M3A = I1;	M3B = K0;
			RouteToC2 = 1;
			
			// Weight Controller
				weights_sram_read_address = 2;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		
		S3 : begin
			// C0 += I0 * K5
			// C1 += I0 * K4 + I1 * K5
			M0A = I0; 	M0B = K5;
			M01A = I0;	M01B = K4;
			M1A = I1;	M1B = K5;
			RouteToC0 = 0;
			
			// C2 += I0 * K2
			// C3 += I0 * K1 + I1 * K2
			M2A = I0;	M2B = K2;
			M23A = I0;	M23B = K1;
			M3A = I1;	M3B = K2;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 2;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		
		S4 : begin
			// C0 += I0 * K6 + I1 * K7
			// C1 += I1 * K6
			M0A = I0; 	M0B = K6;
			M01A = I1;	M01B = K7;
			M1A = I1;	M1B = K6;
			RouteToC0 = 1;
			
			// C2 += I0 * K3 + I1 * K4
			// C3 += I1 * K3
			M2A = I0;	M2B = K3;
			M23A = I1;	M23B = K4;
			M3A = I1;	M3B = K3;
			RouteToC2 = 1;
			
			// Weight Controller
				weights_sram_read_address = 2;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		
		S5 : begin
			// C0 += I0 * K8
			// C1 += I0 * K7 + I1 * K8
			M0A = I0; 	M0B = K8;
			M01A = I0;	M01B = K7;
			M1A = I1;	M1B = K8;
			RouteToC0 = 0;
			
			// C2 += I0 * K5
			// C3 += I0 * K4 + I1 * K5
			M2A = I0;	M2B = K5;
			M23A = I0;	M23B = K4;
			M3A = I1;	M3B = K5;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 2;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		
		S6 : begin
			M0A = 0; 	M0B = 0;
			M01A = 0;	M01B = 0;
			M1A = 0;	M1B = 0;
			RouteToC0 = 0;
			
			// C2 += I0 * K6 + I1 * K7
			// C3 += I1 * K6
			M2A = I0;	M2B = K6;
			M23A = I1;	M23B = K7;
			M3A = I1;	M3B = K6;
			RouteToC2 = 1;
			
			// Weight Controller
				weights_sram_read_address = 2;
			
			// Output
				output_sram_write_data = {RELU_C0,RELU_C1};
				output_sram_write_enable = 1;
		end
		
		S7 : begin
			M0A = 0; 	M0B = 0;
			M01A = 0;	M01B = 0;
			M1A = 0;	M1B = 0;
			RouteToC0 = 0;
			
			// C2 += I0 * K8
			// C3 += I0 * K7 + I1 * K8
			M2A = I0;	M2B = K8;
			M23A = I0;	M23B = K7;
			M3A = I1;	M3B = K8;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 2;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		
		// Covers the reset and prep state, default
		Prep1 : begin
			M0A = 0; 	M0B = 0;
			M01A = 0;	M01B = 0;
			M1A = 0;	M1B = 0;
			RouteToC0 = 0;
			
			M2A = 0;	M2B = 0;
			M23A = 0;	M23B = 0;
			M3A = 0;	M3B = 0;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 2;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		Prep0 : begin
			M0A = 0; 	M0B = 0;
			M01A = 0;	M01B = 0;
			M1A = 0;	M1B = 0;
			RouteToC0 = 0;
			
			M2A = 0;	M2B = 0;
			M23A = 0;	M23B = 0;
			M3A = 0;	M3B = 0;
			RouteToC2 = 0;
			
			// Weight Controller
				weights_sram_read_address = 1;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
		default : begin
			M0A = 0; 	M0B = 0;
			M01A = 0;	M01B = 0;
			M1A = 0;	M1B = 0;
			RouteToC0 = 0;
			
			M2A = 0;	M2B = 0;
			M23A = 0;	M23B = 0;
			M3A = 0;	M3B = 0;
			RouteToC2 = 0;
			
			// Weight Controller
				// =SWITCH(C5, "Reset", 0, "Prep", 1, "S0", 2, "S1", 3, "S2", 4, N("default is zero"))
				weights_sram_read_address = 0;
			
			// Output
				output_sram_write_data = 0;
				output_sram_write_enable = 0;
		end
	endcase
end

// Controller and Datapath Sequential Logic
// Done: Kernel / weight datapath and controller
// Registers
	// state - 4 bits
	// K0 thru K8 - 8 bits each
	// input_sram_read_address and output_sram_write_addresss
always @(posedge clk) begin	
	// have a register buffer on the read input (lag of 1 clock cycle)
	I0 <= input_sram_read_data[15:8];
	I1 <= input_sram_read_data[7:0];
	
	casex (state)
		// Reset is covered in deafult at the bottom
			// Weight
				// Controller
				// =SWITCH(C5, "Reset", 0, "Prep", 1, "S0", 2, "S1", 3, "S2", 4, N("default is zero"))
			// Input
				// Controller
				// =E8+SWITCH(E5, "Prep", 1, "S0", 7, "S1", 1, "S2", 7, "S3", 1, "S4", 7, "S5", 1, "S6", IF(E16,-119,-9), "S7", 1, N("default is zero"))
		
		// Preconditions
			// Requires input_sram_read_address = 0		(For Prep1: assigning I0, I1 to input_sram_read_data IN0 and IN1 -> S0: calculating the first products from I0, I1)
			// Requires weights_sram_read_address = 0 	(For Prep0: assigning K0, K1 to weights_sram_read_data)
		Prep0 : begin	
			// State
				state <= Prep1;
			// Weight
				// Datapath
				K0 <= weights_sram_read_data[15:8];
				K1 <= weights_sram_read_data[7:0];
			// Input
				// TODO: Controller - make sure all this synetesizes into one adder
				input_sram_read_address <= input_sram_read_address + 1;
		end
		
		// Preconditions
			// Requires input_sram_read_data = IN0, IN1	(For Prep1: assigning I0, I1 to input_sram_read_data IN0 and IN1 -> S0: calculating the first products from I0, I1)
			// Requires weights_sram_read_address = 1 	(For Prep1: assigning K2, K3 to weights_sram_read_data)
		Prep1 : begin	// input_sram_read_address was 0 coming in to prep. Input_sram_read_data will show up on this clock cycle
			// State
				state <= S0_Init;
			// Weight
				// Datapath
				K2 <= weights_sram_read_data[15:8];
				K3 <= weights_sram_read_data[7:0];
			// Input
				// TODO: Controller - make sure all this synetesizes into one adder
				input_sram_read_address <= input_sram_read_address + 7;
			// Output
				output_sram_write_addresss <= 0;
		end
		S0 : begin		// Precondition: Requires I0, I1 = IN0, IN1
			{NewCol, DoneSig} <= 0;
			// State
			if (DoneSig)
				state <= Reset;
			else
				state <= S1;
			// Weight
				// Datapath
				K4 <= weights_sram_read_data[15:8];
				K5 <= weights_sram_read_data[7:0];
			// Input
				// Controller
				// The corresponding I0, I1 data from this address will show up at time T + 3
				input_sram_read_address <= input_sram_read_address + 1;
			
			// Output
			if (NewCol)
				output_sram_write_addresss <= output_sram_write_addresss - 90;
			else
				output_sram_write_addresss <= output_sram_write_addresss + 7;
			
		end
		S0_Init : begin		// Precondition: Requires I0, I1 = IN0, IN1
			{NewCol, DoneSig} <= 0;
			// State
			if (DoneSig)
				state <= Reset;
			else
				state <= S1;
			// Weight
				// Datapath
				K4 <= weights_sram_read_data[15:8];
				K5 <= weights_sram_read_data[7:0];
			// Input
				// Controller
				input_sram_read_address <= input_sram_read_address + 1;
			
			// Output
				output_sram_write_addresss <= 0;
			
		end
		S1 : begin
			// State
				state <= S2;
			// Weight
				// Datapath
				K6 <= weights_sram_read_data[15:8];
				K7 <= weights_sram_read_data[7:0];
			// Input
				// Controller
				input_sram_read_address <= input_sram_read_address + 7;
		end
		S2 : begin
			// State
				state <= S3;
			// Weight
				// Datapath
				K8 <= weights_sram_read_data[15:8];
			// Input
				// Controller
				input_sram_read_address <= input_sram_read_address + 1;
		end
		S3 : begin
			// State
				state <= S4;
			// Input
				// Controller - make sure all this synetesizes into one adder
				input_sram_read_address <= input_sram_read_address + 7;
		end
		S4 : begin
			// State
				state <= S5;
			// Input
				// Controller
				input_sram_read_address <= input_sram_read_address + 1;
			
			NewCol <= (inputRow==15);			// Signal to move on to a new column if the row is 15
			DoneSig <= (inputRow==15)&(inputCol>=6);	// Signal that we are done with the convolution if we are moving on to a new column and we are on the last column
		end
		S5 : begin
			// State
				state <= S6;
			// Input
				// Controller - make sure all this synetesizes into one adder
				if (NewCol)
					input_sram_read_address <= input_sram_read_address - 120;
				else
					input_sram_read_address <= input_sram_read_address - 9;
		end
		S6 : begin
			// State
				// DONE: inserted logic here
				// IF(L17,"S7_Done",IF(L16,"S7_NextCol","S7"))
				state <= S7;
			// Input
				// Controller
				// =E8+SWITCH(E5, "Prep", 1, "S0", 7, "S1", 1, "S2", 7, "S3", 1, "S4", 7, "S5", 1, "S6", IF(E16,-119,-9), "S7", 1, N("default is zero"))
				// TODO: can combine this with the if logic above
				input_sram_read_address <= input_sram_read_address + 1;
				
			// Output
				output_sram_write_addresss <= output_sram_write_addresss + 7;
		end
		S7 : begin
			// State
				state <= S0;
			// Input
				// Controller - make sure all this synetesizes into one adder
				input_sram_read_address <= input_sram_read_address + 7;
			// Output
				
		end
		// Cover reset and default in the same state
		default : begin
			{NewCol, DoneSig} <= 0;
			// State
				if (dut_run)
					state <= Prep0;
			// Input
				// Controller - make sure all this synetesizes into one adder
				input_sram_read_address <= 0;
			// Output
				output_sram_write_addresss <= 0;
		end
	endcase
	if (reset_b == 0)
		state <= Reset;
end
endmodule
