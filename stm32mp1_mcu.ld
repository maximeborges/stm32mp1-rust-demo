/* # Developer notes

- Symbols that start with a double underscore (__) are considered "private"

- Symbols that start with a single underscore (_) are considered "semi-public"; they can be
  overridden in a user linker script, but should not be referred from user code (e.g. `extern "C" {
  static mut __sbss }`).

- `EXTERN` forces the linker to keep a symbol in the final binary. We use this to make sure a
  symbol if not dropped if it appears in or near the front of the linker arguments and "it's not
  needed" by any of the preceding objects (linker arguments)

- `PROVIDE` is used to provide default values that can be overridden by a user linker script

- On alignment: it's important for correctness that the VMA boundaries of both .bss and .data *and*
  the LMA of .data are all 4-byte aligned. These alignments are assumed by the RAM initialization
  routine. There's also a second benefit: 4-byte aligned boundaries means that you won't see
  "Address (..) is out of bounds" in the disassembly produced by `objdump`.
*/

MEMORY
{
  /* NOTE K = KiBi = 1024 bytes */
  /* For the STM32MP1 IPU1 */
  /* We don't really have FLASH and RAM, just DDR
     but we keep the two segments to compatibility with cortex-m-rt */
  m_interrupts (RX)  : ORIGIN = 0x00000000, LENGTH = 0x00000298
  FLASH        (RWX) : ORIGIN = 0x10000000, LENGTH = 282K
  RAM          (RW)  : ORIGIN = 0x10046800, LENGTH = 64K
  IPC_DATA     (RW)  : ORIGIN = 0x10056800, LENGTH = 32K
}

/* # Entry point = reset vector */
ENTRY(ResetSTM32MP1);
EXTERN(__RESET_VECTOR_STM32MP1); /* depends on the `ResetSTM32MP1` symbol */

/* # Exception vectors */
/* This is effectively weak aliasing at the linker level */
/* The user can override any of these aliases by defining the corresponding symbol themselves (cf.
   the `exception!` macro) */
EXTERN(__EXCEPTIONS); /* depends on all the these PROVIDED symbols */

EXTERN(DefaultHandler);

PROVIDE(NonMaskableInt = DefaultHandler);
EXTERN(HardFault);
PROVIDE(MemoryManagement = DefaultHandler);
PROVIDE(BusFault = DefaultHandler);
PROVIDE(UsageFault = DefaultHandler);
PROVIDE(SecureFault = DefaultHandler);
PROVIDE(SVCall = DefaultHandler);
PROVIDE(DebugMonitor = DefaultHandler);
PROVIDE(PendSV = DefaultHandler);
PROVIDE(SysTick = DefaultHandler);

/* # Interrupt vectors */
EXTERN(__INTERRUPTS); /* `static` variable similar to `__EXCEPTIONS` */

/* # Pre-initialization function */
/* If the user overrides this using the `pre_init!` macro or by creating a `__pre_init` function,
   then the function this points to will be called before the RAM is initialized. */
PROVIDE(__pre_init = DefaultPreInit);

/* # User overridable symbols I */
/* Lets the user place the stack in a different RAM region */
PROVIDE(_stack_start = ORIGIN(RAM) + LENGTH(RAM));


/* Set address for the tracebuffer*/
.tracebuffer  = ORIGIN(IPC_DATA);

/* # Sections */
SECTIONS
{
  /* The startup code into ROM memory */
  .vector_table ORIGIN(m_interrupts) : ALIGN(4)
  {
    /* Initial Stack Pointer (SP) value */
    __STACK_START = .; /* Just to get a nicer name in the disassembly */
    LONG(_stack_start);

    /* Reset vector */
    KEEP(*(.vector_table.reset_vector_stm32mp1)); /* this is `__RESET_VECTOR_STM32MP1` symbol */
    __reset_vector = ABSOLUTE(.);

    /* Exceptions */
    KEEP(*(.vector_table.exceptions)); /* this is `__EXCEPTIONS` symbol */
    __eexceptions = ABSOLUTE(.);

    /* Device specific interrupts */
    KEEP(*(.vector_table.interrupts)); /* this is `__INTERRUPTS` symbol */
    __einterrupts = ABSOLUTE(.);
  } > m_interrupts

  /* ## Sections in FLASH */
  /* ### .text */
  .text ORIGIN(FLASH) : ALIGN(4)
  {
    __STACK_START = .; /* Just to get a nicer name in the disassembly */
    LONG(_stack_start);
    *(.text .text.*);
    __etext = ABSOLUTE(.);
  } > FLASH

  /* ### .rodata */
  .rodata :
  {
    . = ALIGN(4); /* 4-byte align the start (VMA) of this section */
    /* __srodata = ABSOLUTE(.); */

    KEEP(*(.vector_table.reset_vector)); /* this is `__RESET_VECTOR` symbol */
    *(.rodata .rodata.*);

    . = ALIGN(4); /* 4-byte align the end (VMA) of this section */
    __erodata = ABSOLUTE(.);
  } > FLASH

  /* ## Sections in RAM */
  /* ### .data */
  .data :
  {
    . = ALIGN(4); /* 4-byte align the start (VMA) of this section */
    __sdata = ABSOLUTE(.);
    __edata = ABSOLUTE(.);

    *(.data .data.*);

    . = ALIGN(4); /* 4-byte align the end (VMA) of this section */
  } > RAM

  /* ### .bss */
  .bss :
  {
    . = ALIGN(4); /* 4-byte align the start (VMA) of this section */
    __sbss = ABSOLUTE(.);

    *(.bss .bss.*);

    . = ALIGN(4); /* 4-byte align the end (VMA) of this section */
    __ebss = ABSOLUTE(.);
  } > RAM

  /* ## Fake output .got section */
  /* Dynamic relocations are unsupported. This section is only used to detect relocatable code in
     the input files and raise an error if relocatable code is found */
  .got :
  {
    __sgot = ABSOLUTE(.);
    KEEP(*(.got .got.*));
    __egot = ABSOLUTE(.);
  } > FLASH

  /* This is how we communicate with the kernel */
  /*.ipc_data : {
      KEEP(*(.tracebuffer .tracebuffer.*))
      KEEP(*(.ipc_data .ipc_data.*))
  } > IPC_DATA*/

  /* The kernel looks for a section with this name */
  .resource_table : {
      KEEP(*(.resource_table))
  } > FLASH

  /* The kernel looks for a section with this name */
  .version : {
      KEEP(*(.version))
  } > FLASH

  /* ## Discarded sections */
  /DISCARD/ :
  {
    /* Unused exception related info that only wastes space */
    *(.ARM.exidx.*);
  }
}

/* # User overridable symbols II */
/* (The user overridable symbols are split in two parts because LLD demands that the RHS of PROVIDE
    to be defined before the PROVIDE invocation) */
/* Lets the user override this to place .text a bit further than the vector table. Required by
microcontrollers that store their configuration right after the vector table. */
PROVIDE(_stext = __einterrupts);

/* Default IRQ handlers as weak symbols */
PROVIDE(WWDG1_IRQHandler = DefaultHandler);
PROVIDE(PVD_AVD_IRQHandler = DefaultHandler);
PROVIDE(TAMP_IRQHandler = DefaultHandler);
PROVIDE(RTC_WKUP_ALARM_IRQHandler = DefaultHandler);
PROVIDE(RESERVED4_IRQHandler = DefaultHandler);
PROVIDE(RCC_IRQHandler = DefaultHandler);
PROVIDE(EXTI0_IRQHandler = DefaultHandler);
PROVIDE(EXTI1_IRQHandler = DefaultHandler);
PROVIDE(EXTI2_IRQHandler = DefaultHandler);
PROVIDE(EXTI3_IRQHandler = DefaultHandler);
PROVIDE(EXTI4_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream0_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream1_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream2_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream3_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream4_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream5_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream6_IRQHandler = DefaultHandler);
PROVIDE(ADC1_IRQHandler = DefaultHandler);
PROVIDE(FDCAN1_IT0_IRQHandler = DefaultHandler);
PROVIDE(FDCAN2_IT0_IRQHandler = DefaultHandler);
PROVIDE(FDCAN1_IT1_IRQHandler = DefaultHandler);
PROVIDE(FDCAN2_IT1_IRQHandler = DefaultHandler);
PROVIDE(EXTI5_IRQHandler = DefaultHandler);
PROVIDE(TIM1_BRK_IRQHandler = DefaultHandler);
PROVIDE(TIM1_UP_IRQHandler = DefaultHandler);
PROVIDE(TIM1_TRG_COM_IRQHandler = DefaultHandler);
PROVIDE(TIM1_CC_IRQHandler = DefaultHandler);
PROVIDE(TIM2_IRQHandler = DefaultHandler);
PROVIDE(TIM3_IRQHandler = DefaultHandler);
PROVIDE(TIM4_IRQHandler = DefaultHandler);
PROVIDE(I2C1_EV_IRQHandler = DefaultHandler);
PROVIDE(I2C1_ER_IRQHandler = DefaultHandler);
PROVIDE(I2C2_EV_IRQHandler = DefaultHandler);
PROVIDE(I2C2_ER_IRQHandler = DefaultHandler);
PROVIDE(SPI1_IRQHandler = DefaultHandler);
PROVIDE(SPI2_IRQHandler = DefaultHandler);
PROVIDE(USART1_IRQHandler = DefaultHandler);
PROVIDE(USART2_IRQHandler = DefaultHandler);
PROVIDE(USART3_IRQHandler = DefaultHandler);
PROVIDE(EXTI10_IRQHandler = DefaultHandler);
PROVIDE(RTC_TIMESTAMP_IRQHandler = DefaultHandler);
PROVIDE(EXTI11_IRQHandler = DefaultHandler);
PROVIDE(TIM8_BRK_IRQHandler = DefaultHandler);
PROVIDE(TIM8_UP_IRQHandler = DefaultHandler);
PROVIDE(TIM8_TRG_COM_IRQHandler = DefaultHandler);
PROVIDE(TIM8_CC_IRQHandler = DefaultHandler);
PROVIDE(DMA1_Stream7_IRQHandler = DefaultHandler);
PROVIDE(FMC_IRQHandler = DefaultHandler);
PROVIDE(SDMMC1_IRQHandler = DefaultHandler);
PROVIDE(TIM5_IRQHandler = DefaultHandler);
PROVIDE(SPI3_IRQHandler = DefaultHandler);
PROVIDE(UART4_IRQHandler = DefaultHandler);
PROVIDE(UART5_IRQHandler = DefaultHandler);
PROVIDE(TIM6_IRQHandler = DefaultHandler);
PROVIDE(TIM7_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream0_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream1_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream2_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream3_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream4_IRQHandler = DefaultHandler);
PROVIDE(ETH1_IRQHandler = DefaultHandler);
PROVIDE(ETH1_WKUP_IRQHandler = DefaultHandler);
PROVIDE(FDCAN_CAL_IRQHandler = DefaultHandler);
PROVIDE(EXTI6_IRQHandler = DefaultHandler);
PROVIDE(EXTI7_IRQHandler = DefaultHandler);
PROVIDE(EXTI8_IRQHandler = DefaultHandler);
PROVIDE(EXTI9_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream5_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream6_IRQHandler = DefaultHandler);
PROVIDE(DMA2_Stream7_IRQHandler = DefaultHandler);
PROVIDE(USART6_IRQHandler = DefaultHandler);
PROVIDE(I2C3_EV_IRQHandler = DefaultHandler);
PROVIDE(I2C3_ER_IRQHandler = DefaultHandler);
PROVIDE(USBH_OHCI_IRQHandler = DefaultHandler);
PROVIDE(USBH_EHCI_IRQHandler = DefaultHandler);
PROVIDE(EXTI12_IRQHandler = DefaultHandler);
PROVIDE(EXTI13_IRQHandler = DefaultHandler);
PROVIDE(DCMI_IRQHandler = DefaultHandler);
PROVIDE(CRYP1_IRQHandler = DefaultHandler);
PROVIDE(HASH1_IRQHandler = DefaultHandler);
PROVIDE(FPU_IRQHandler = DefaultHandler);
PROVIDE(UART7_IRQHandler = DefaultHandler);
PROVIDE(UART8_IRQHandler = DefaultHandler);
PROVIDE(SPI4_IRQHandler = DefaultHandler);
PROVIDE(SPI5_IRQHandler = DefaultHandler);
PROVIDE(SPI6_IRQHandler = DefaultHandler);
PROVIDE(SAI1_IRQHandler = DefaultHandler);
PROVIDE(LTDC_IRQHandler = DefaultHandler);
PROVIDE(LTDC_ER_IRQHandler = DefaultHandler);
PROVIDE(ADC2_IRQHandler = DefaultHandler);
PROVIDE(SAI2_IRQHandler = DefaultHandler);
PROVIDE(QUADSPI_IRQHandler = DefaultHandler);
PROVIDE(LPTIM1_IRQHandler = DefaultHandler);
PROVIDE(CEC_IRQHandler = DefaultHandler);
PROVIDE(I2C4_EV_IRQHandler = DefaultHandler);
PROVIDE(I2C4_ER_IRQHandler = DefaultHandler);
PROVIDE(SPDIF_RX_IRQHandler = DefaultHandler);
PROVIDE(OTG_IRQHandler = DefaultHandler);
PROVIDE(RESERVED99_IRQHandler = DefaultHandler);
PROVIDE(IPCC_RX0_IRQHandler = DefaultHandler);
PROVIDE(IPCC_TX0_IRQHandler = DefaultHandler);
PROVIDE(DMAMUX1_OVR_IRQHandler = DefaultHandler);
PROVIDE(IPCC_RX1_IRQHandler = DefaultHandler);
PROVIDE(IPCC_TX1_IRQHandler = DefaultHandler);
PROVIDE(CRYP2_IRQHandler = DefaultHandler);
PROVIDE(HASH2_IRQHandler = DefaultHandler);
PROVIDE(I2C5_EV_IRQHandler = DefaultHandler);
PROVIDE(I2C5_ER_IRQHandler = DefaultHandler);
PROVIDE(GPU_IRQHandler = DefaultHandler);
PROVIDE(DFSDM1_FLT0_IRQHandler = DefaultHandler);
PROVIDE(DFSDM1_FLT1_IRQHandler = DefaultHandler);
PROVIDE(DFSDM1_FLT2_IRQHandler = DefaultHandler);
PROVIDE(DFSDM1_FLT3_IRQHandler = DefaultHandler);
PROVIDE(SAI3_IRQHandler = DefaultHandler);
PROVIDE(DFSDM1_FLT4_IRQHandler = DefaultHandler);
PROVIDE(TIM15_IRQHandler = DefaultHandler);
PROVIDE(TIM16_IRQHandler = DefaultHandler);
PROVIDE(TIM17_IRQHandler = DefaultHandler);
PROVIDE(TIM12_IRQHandler = DefaultHandler);
PROVIDE(MDIOS_IRQHandler = DefaultHandler);
PROVIDE(EXTI14_IRQHandler = DefaultHandler);
PROVIDE(MDMA_IRQHandler = DefaultHandler);
PROVIDE(DSI_IRQHandler = DefaultHandler);
PROVIDE(SDMMC2_IRQHandler = DefaultHandler);
PROVIDE(HSEM_IT2_IRQHandler = DefaultHandler);
PROVIDE(DFSDM1_FLT5_IRQHandler = DefaultHandler);
PROVIDE(EXTI15_IRQHandler = DefaultHandler);
PROVIDE(nCTIIRQ1_IRQHandler = DefaultHandler);
PROVIDE(nCTIIRQ2_IRQHandler = DefaultHandler);
PROVIDE(TIM13_IRQHandler = DefaultHandler);
PROVIDE(TIM14_IRQHandler = DefaultHandler);
PROVIDE(DAC_IRQHandler = DefaultHandler);
PROVIDE(RNG1_IRQHandler = DefaultHandler);
PROVIDE(RNG2_IRQHandler = DefaultHandler);
PROVIDE(I2C6_EV_IRQHandler = DefaultHandler);
PROVIDE(I2C6_ER_IRQHandler = DefaultHandler);
PROVIDE(SDMMC3_IRQHandler = DefaultHandler);
PROVIDE(LPTIM2_IRQHandler = DefaultHandler);
PROVIDE(LPTIM3_IRQHandler = DefaultHandler);
PROVIDE(LPTIM4_IRQHandler = DefaultHandler);
PROVIDE(LPTIM5_IRQHandler = DefaultHandler);
PROVIDE(ETH1_LPI_IRQHandler = DefaultHandler);
PROVIDE(RESERVED143_IRQHandler = DefaultHandler);
PROVIDE(MPU_SEV_IRQHandler = DefaultHandler);
PROVIDE(RCC_WAKEUP_IRQHandler = DefaultHandler);
PROVIDE(SAI4_IRQHandler = DefaultHandler);
PROVIDE(DTS_IRQHandler = DefaultHandler);
PROVIDE(RESERVED148_IRQHandler = DefaultHandler);
PROVIDE(WAKEUP_PIN_IRQHandler = DefaultHandler);

/* # Hardcoded symbols */
/* Place `.bss` at the start of the RAM region */
__sidata = LOADADDR(.data);
/* Place the heap right after `.bss` and `.data` */
__sheap = __ebss;

/* # Sanity checks */

/* Do not exceed this mark in the error messages below                                    | */
ASSERT(__reset_vector == ORIGIN(m_interrupts) + 0x8, "
cortex-m-rt: The reset vector is missing. This is a bug in cortex-m-rt. Please file a bug
report at: https://github.com/japaric/cortex-m-rt/issues");

ASSERT(__eexceptions - ORIGIN(m_interrupts) == 0x40, "
cortex-m-rt: The exception vectors are missing. This is a bug in cortex-m-rt. Please file
a bug report at: https://github.com/japaric/cortex-m-rt/issues");

ASSERT(__sheap >= __ebss, "
cortex-m-rt: The heap overlaps with the .bss section. This is a bug in cortex-m-rt. Please
file a bug report at: https://github.com/japaric/cortex-m-rt/issues");

ASSERT(__sheap >= __edata, "
cortex-m-rt: The heap overlaps with the .data section. This is a bug in cortex-m-rt.
Please file a bug report at: https://github.com/japaric/cortex-m-rt/issues");

ASSERT(__einterrupts - __eexceptions > 0, "
cortex-m-rt: The interrupt vectors are missing. Possible solutions, from most likely to
less likely:
- Link to a device crate
- Disable the 'device' feature of cortex-m-rt to build a generic application (a dependency
  may be enabling it)
- Supply the interrupt handlers yourself. Check the documentation for details.");

ASSERT(__einterrupts <= _stext, "
cortex-m-rt: The '.text' section can't be placed inside the '.vector_table' section. Set
'_stext' to an address greater than '__einterrupts' (cf. `nm` output)");

ASSERT(_stext < ORIGIN(FLASH) + LENGTH(FLASH), "
cortex-m-rt The '.text' section must be placed inside the FLASH memory. Set '_stext' to an
address smaller than 'ORIGIN(FLASH) + LENGTH(FLASH)");

/* This has been temporarily omitted because it's not supported by LLD */
/* ASSERT(__sbss % 4 == 0 && __ebss % 4 == 0, " */
/* .bss is not 4-byte aligned at its boundaries. This is a cortex-m-rt bug."); */

/* ASSERT(__sdata % 4 == 0 && __edata % 4 == 0, " */
/* .data is not 4-byte aligned at its boundaries. This is a cortex-m-rt bug."); */

/* ASSERT(__sidata % 4 == 0, " */
/* __sidata is not 4-byte aligned. This is a cortex-m-rt bug."); */

ASSERT(__sgot == __egot, "
.got section detected in the input object files. Dynamic relocations are not supported.
If you are linking to C code compiled using the `cc` crate then modify your build script
to compile the C code _without_ the -fPIC flag. See the documentation of the
`cc::Build.pic` method for details.");
/* Do not exceed this mark in the error messages above                                    | */

ASSERT(__einterrupts - __eexceptions <= 0x3c0, "
There can't be more than 240 interrupt handlers. This may be a bug in
your device crate, or you may have registered more than 240 interrupt
handlers.");

