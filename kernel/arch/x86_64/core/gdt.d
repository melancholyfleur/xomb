/*
 * gdt.d
 *
 * The implementation of the 64 bit x86 Global Descriptor Table
 *
 */

module kernel.arch.x86_64.core.gdt;

// Import BitField!()
import kernel.core.util;

// Import ErrorVal
import kernel.core.error;

struct GDT {
static:

	// This list provides the types allowed for a system segment descriptor
	enum SystemSegmentType {
		LocalDescriptorTable	= 0b0010,
		AvailableTSS			= 0b1001,
		BusyTSS					= 0b1011,
		CallGate				= 0b1100,
		InterruptGate			= 0b1110,
		TrapGate				= 0b1111
	}

	// this function will set up the GDT
	ErrorVal initialize() {
		// The limit is the size of the table minus 1
		gdtBase.limit	= (SegmentDescriptor.sizeof * entries.length) - 1;
		gdtBase.base	= cast(ulong)entries.ptr;

		// Define the table:

		// Two null descriptors must be defined
		setNull(0);
		setNull(1);

		// Set up the code and data segment permissions for the kernel
		// This corresponds with CS_KERNEL
		setCodeSegment(2, false, 0, true);
		setDataSegment(3, true, 0);
		setDataSegment(4, true, 0);

		// Segments 6 and 7 are for the TSS, and will be installed within
		// that module

		// Set up the code and data segment for the user
		// Corresponds with CS_USER
		setDataSegment(8, true, 3);
		setCodeSegment(9, true, 3, true);

		return ErrorVal.Success;
	}

	ErrorVal install() {
		asm {
			lgdt [gdtBase];
		}
		return ErrorVal.Success;
	}


	// -- The following functions mutate the entries of the GDT -- //


	// This will clear out an entry, which is necessary for the first entry
	void setNull(uint index) {
		entries[index].value = 0;
	}

	// This will define an entry for a code segment
	void setCodeSegment(uint index, bool conforming, ubyte DPL, bool present) {
		entries[index].codeSegment = CodeSegmentDescriptor.init;

		with(entries[index].codeSegment) {
			c = conforming;
			dpl = DPL;
			p = present;
			l = true;
			d = false;
		}
	}

	// This will define an entry for a data segment
	void setDataSegment(uint index, bool present, ubyte DPL) {
		entries[index].dataSegment = DataSegmentDescriptor.init;

		with(entries[index].dataSegment) {
			p = present;
			dpl = DPL;
		}
	}

	// This will define a system segment, which will be used to define the TSS
	void setSystemSegment(uint index, uint limit, ulong base, SystemSegmentType segType, ubyte DPL, bool present, bool avail, bool granularity) {
		entries[index].systemSegmentLo = SystemSegmentDescriptor.init;
		entries[index+1].systemSegmentHi = SystemSegmentExtension.init;

		with(entries[index].systemSegmentLo) {
			baseLo = (base & 0xffff);
			baseMidLo = (base >> 16) & 0xff;
			baseMidHi = (base >> 24) & 0xff;

			limitLo = limit & 0xffff;
			limitHi = (limit >> 16) & 0xf;

			type = segType;
			dpl = DPL;
			p = present;
			avl = avail;
			g = granularity;
		}

		with(entries[index+1].systemSegmentHi) {
			baseHi = (base >> 32) & 0xffffffff;
		}
	}

private:


	// -- Descriptors -- //


	// This structure is the one pointed to by the hardware's GDTR register.
	// It is loaded via the LGDT instruction
	align(1) struct GDTBase {
		ushort limit;
		ulong base;
	}

	align(1) struct CodeSegmentDescriptor {
		ushort limit	= 0x0000;
		ushort base		= 0xffff;
		ubyte zero1		= 0;
		ubyte flags1	= 0b11111101;
		ubyte flags2	= 0b00000000;
		ubyte zero2		= 0;

		mixin(Bitfield!(flags1, "zero3", 2, "c", 1, "ones0", 2, "dpl", 2, "p", 1));
		mixin(Bitfield!(flags2, "zero4", 5, "l", 1, "d", 1, "zero5", 1));
	}

	static assert(CodeSegmentDescriptor.sizeof == 8);

	align(1) struct DataSegmentDescriptor {
		ushort limit	= 0x0000;
		ushort base		= 0xffff;
		ubyte zero1		= 0;
		ubyte flags1	= 0b11110011;
		ubyte flags2	= 0b11001111;
		ubyte zero2		= 0;

		mixin(Bitfield!(flags1, "zero4", 5, "dpl", 2, "p", 1));
	}

	static assert(DataSegmentDescriptor.sizeof == 8);


	// The system segment descriptor defines the position in memory
	// of a core structure. For this code, only the TSS is defined
	// in this manner, and one must exist.

	// This descriptor is, for some reason, twice the size of any
	// other descriptor. For ease of use, it has been split into
	// two structures. The first structure is the low half, and the
	// second is the high half.
	align(1) struct SystemSegmentDescriptor {
		// Refer to the Intel Docs or the 'GDT' article on wiki.xomb.org
		ushort limitLo;
		ushort baseLo;
		ubyte baseMidLo;
		ubyte flags1;
		ubyte flags2;
		ubyte baseMidHi;

		// Bitfields to define flags
		mixin(Bitfield!(flags1, "type", 4, "zero0", 1, "dpl", 2, "p", 1));
		mixin(Bitfield!(flags2, "limitHi", 4, "avl", 1, "zero1", 2, "g", 1));
	}

	align(1) struct SystemSegmentExtension {
		uint baseHi;
		uint reserved = 0;
	}

	// compile check for correctness
	static assert(SystemSegmentDescriptor.sizeof == 8);


	// This structure is the combination of all other structures.
	// It defines generically a single entry in the GDT. (Or half of
	// one if it is the system segment descriptor)
	align(1) union SegmentDescriptor {
		DataSegmentDescriptor		dataSegment;
		CodeSegmentDescriptor		codeSegment;
		SystemSegmentDescriptor		systemSegmentLo;
		SystemSegmentExtension		systemSegmentHi;

		// for setting explicit values
		ulong value;
	}

	// compile check for correctness
	static assert(SegmentDescriptor.sizeof == 8);


	// -- The GDT Table -- //


	// The GDT Table itself is defined here as an array of
	// descriptors and the base data structure.

	// The base data structure, which will be loaded via LGDT
	GDTBase gdtBase;

	// These are the complete set of entries within the GDT
	SegmentDescriptor[64] entries;
}
