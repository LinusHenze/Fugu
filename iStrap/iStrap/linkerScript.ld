ENTRY(main_iStrap)

SECTIONS
{
    . = 0x180001000;

    .text.boot : {
        *(.text.boot)
    }

    . = ALIGN(8);

    .text : {
        *(.text)
    }

    . = ALIGN(8);

    .data : {
        *(.data)
    }

    . = ALIGN(8);

    .rodata : {
        *(.rodata)
    }
    
    . = ALIGN(8);
    
    .bss : {
        *(.bss)
    }

    . = ALIGN(8);

    .got : {
        *(.got)
    }

    . = ALIGN(8);

    .rela.plt : {
        *(.rela.plt)
    }

    . = ALIGN(8);

    .data_at_the_end : {
        *(.end_data)
    }

    appended_data_start = .;
}
