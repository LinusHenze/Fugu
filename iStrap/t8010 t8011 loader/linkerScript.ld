ENTRY(start)

SECTIONS
{
    .text : {
        *(.text.boot)
        *(.text)
    }

    .data : {
        *(.data)
    }

    .rodata : {
        *(.rodata)
    }

    .data_at_the_end : {
        *(.end_data)
    }

    . = 0x1000;

    main_iStrap = .;
}
