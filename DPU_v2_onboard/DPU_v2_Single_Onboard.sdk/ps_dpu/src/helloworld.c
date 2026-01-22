#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xgpio.h"
#include "xil_io.h"
#include "xil_types.h"
#include "sleep.h"
#include "xil_cache.h"

#define BRAM_ACT_BASE XPAR_BRAM_0_BASEADDR
#define BRAM_WGT_BASE XPAR_BRAM_1_BASEADDR
#define GPIO_DEVICE_ID XPAR_GPIO_0_DEVICE_ID

// GPIO Channels
#define GPIO_CHANNEL_START 1
#define GPIO_CHANNEL_DONE  2

#define BRAM_OFFSET_INPUT  0
#define BRAM_OFFSET_OUTPUT 4096

XGpio Gpio;

extern char inbyte(void);
extern void outbyte(char c);

u32 read_u32_from_uart() {
    u32 val = 0;
    u8 b0 = (u8)inbyte();
    u8 b1 = (u8)inbyte();
    u8 b2 = (u8)inbyte();
    u8 b3 = (u8)inbyte();
    val = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
    return val;
}

void write_u32_to_uart(u32 val) {
    outbyte((char)(val & 0xFF));
    outbyte((char)((val >> 8) & 0xFF));
    outbyte((char)((val >> 16) & 0xFF));
    outbyte((char)((val >> 24) & 0xFF));
}

int main()
{
    int Status;
    u32 WeightSize, InputSize;
    u32 i;
    u8 data_byte;

    init_platform();
    
    Xil_DCacheDisable();

    // Initialize GPIO
    Status = XGpio_Initialize(&Gpio, GPIO_DEVICE_ID);
    if (Status != XST_SUCCESS) {
        xil_printf("Gpio Initialization Failed\r\n");
        cleanup_platform();
        return XST_FAILURE;
    }

    // Channel 1: Output (Start Signal) -> 0x0
    XGpio_SetDataDirection(&Gpio, GPIO_CHANNEL_START, 0x0);
    // Channel 2: Input (Done Signal) -> 0xFFFFFFFF
    XGpio_SetDataDirection(&Gpio, GPIO_CHANNEL_DONE, 0xFFFFFFFF);

    // Initial State: Start = 0
    XGpio_DiscreteWrite(&Gpio, GPIO_CHANNEL_START, 0);

    while (1) {
        // 1. Handshake
        char cmd = inbyte();
        if (cmd != (char)0xA5) {
        	continue;
        }
        outbyte((char)0x5A); // Ack

        // 2. Receive Weights
        WeightSize = read_u32_from_uart();
        for (i = 0; i < WeightSize; i++) {
        	data_byte = (u8)inbyte();
        	Xil_Out8(BRAM_WGT_BASE + i, data_byte);
        }
        outbyte(0x06); // Ack Weights

        // 3. Receive Input Activations
        InputSize = read_u32_from_uart();
        for (i = 0; i < InputSize; i++) {
        	data_byte = (u8)inbyte();
        	Xil_Out8(BRAM_ACT_BASE + BRAM_OFFSET_INPUT + i, data_byte);
        }
        outbyte(0x06); // Ack Inputs

        // 4. Start Computation
        XGpio_DiscreteWrite(&Gpio, GPIO_CHANNEL_START, 1);

        // Wait for Done
        volatile u32 DoneSignal = 0;
        while (DoneSignal == 0) {
        	DoneSignal = XGpio_DiscreteRead(&Gpio, GPIO_CHANNEL_DONE);
        	DoneSignal &= 0x1;
        }

        XGpio_DiscreteWrite(&Gpio, GPIO_CHANNEL_START, 0);

        // 5. Send Results
        // Send a byte to indicate completion
        outbyte(0x01);

        u32 ResultSize = 4096;
        write_u32_to_uart(ResultSize);

        for (i = 0; i < ResultSize; i++) {
        	data_byte = Xil_In8(BRAM_ACT_BASE + BRAM_OFFSET_OUTPUT + i);
        	outbyte((char)data_byte);
        }
    }

    cleanup_platform();
    return 0;
}
