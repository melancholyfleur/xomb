/*
 * private.d
 *
 * private L2 cache (sorta).
 *
 */

module kernel.mem.private_cache;

// Import system info to get info about RAM
import kernel.system.info;

// Import kernel foo
import kernel.core.error;
import kernel.core.log;
import kernel.core.kprintf;

// Import arch foo
import architecture.vm;

//Import the Bitmap.bitmap stuff
import Bitmap = kernel.mem.bitmap;

import kernel.system.definitions;
import architecture.cpu;

ErrorVal initialize() {

	 //need to determine number of sets for the L2 cache
	 uint num_sets = System.processorInfo[Cpu.identifier].L2Cache.length;
	 num_sets = num_sets/(System.processorInfo[Cpu.identifier].L2Cache.associativity * System.processorInfo[Cpu.identifier].L2Cache.blockSize);

	kprintfln!("PageColor: L2 A: {} B: {} C: {}")(
		System.processorInfo[Cpu.identifier].L2Cache.associativity,
		System.processorInfo[Cpu.identifier].L2Cache.blockSize,
		System.processorInfo[Cpu.identifier].L2Cache.length);


	 kprintfln!("PageColor: num_sets: {}")(num_sets);
	 	 
	 uint set_bits = 0;
	 uint temp = num_sets;
	 while(temp > 1) {
	 	    set_bits++;
		    temp = temp/2;
	 }
	 
	 uint block_bits = 0;
	 temp = System.processorInfo[Cpu.identifier].L2Cache.blockSize;	 while(temp > 1) {
	 	    block_bits++;
		    temp = temp/2;
	 }

	uint page_bits = 0;
	temp = VirtualMemory.getPageSize();
	while(temp > 1) {
		   page_bits++;
		   temp = temp/2;
	}
	kprintfln!("block bits: {} set bits: {} page bits: {}")(block_bits, set_bits, page_bits);

	color_bits = set_bits + block_bits - page_bits;
	color_mask = (((1 << color_bits)-1) << page_bits);
	kprintfln!("color_mask: {b}")(color_mask);
	return Bitmap.initialize();
}

ErrorVal reportCore() {
	return ErrorVal.Success;
}

void* allocPage() {
	return Bitmap.allocPage();
}

void* allocPage(void* virtAddr) {
	// Find a page
	ulong index = findPage(virtAddr);

	if (index == 0xffffffffffffffffUL) {
		return null;
	}

	// Return the address
	return cast(void*)(index * VirtualMemory.getPageSize());
}

ErrorVal freePage(void* address) {
	 return Bitmap.freePage(address);
}

uint length() {
	return Bitmap.length();
}

ubyte* start() {
       return Bitmap.start();
}

ubyte* virtualStart() {
       return Bitmap.virtualStart();
}

void virtualStart(void* newAddr) {
     return Bitmap.virtualStart(newAddr);
}

private {
	uint color_bits; //defines the #of color_bits
	ulong color_mask;

	// A helper function to mark off a range of memory
	void markOffRegion(void* start, ulong length) {
		// When aligning to a page, floor the start, ceiling the end

		// Get the first pageIndex
		ulong startAddr, endAddr;

		// Get the logical range
		startAddr = cast(ulong)start;
		endAddr = startAddr + length;
		startAddr -= startAddr % VirtualMemory.getPageSize();
		if ((endAddr % VirtualMemory.getPageSize())>0) {
			endAddr += VirtualMemory.getPageSize() - (endAddr % VirtualMemory.getPageSize());
		}

		// startAddr is the start address of the region aligned to a page
		// endAddr is the end address of the region aligned to a page

		// Now, we will get the page indices and mark off each page
		ulong pageIndex = startAddr / VirtualMemory.getPageSize();
		ulong maxIndex = (endAddr - startAddr) / VirtualMemory.getPageSize();
		maxIndex += pageIndex;

		for(; pageIndex<maxIndex; pageIndex++) {
			markOffPage(pageIndex);
		}
	}

	void markOffPage(ulong pageIndex) {
		// Go to the specific ulong
		// Set the corresponding bit

		if (pageIndex >= Bitmap.totalPages) {
			return;
		}

		ulong byteNumber = pageIndex / 64;
		ulong bitNumber = pageIndex % 64;

		Bitmap.bitmap[byteNumber] |= (1 << bitNumber);
	}

	// Returns the page index of a free page
	ulong findPage(void * virtAddr) {
		ulong* curPtr = Bitmap.bitmap;
		ulong curIndex = 0;
		
		ulong offset = (1 << color_bits)/System.numProcessors;
		//kprintfln!("num Processors: {}, offset: {}")(System.numProcessors, offset);
		ulong mask = (1 << color_bits) -1;
		//kprintfln!("findPage: {x} color: {x}:{x} curPtr: {x}")(virtAddr, color, color_shift, curPtr);

		while(true) {
			// this would mean that there is a 0 in there somewhere
			if (*curPtr < 0xffffffffffffffffUL) {
				// look for the 0
				ulong tmpVal = *curPtr;
				ulong subIndex = curIndex;

				for (uint b; b < 64; b++) {
					if((tmpVal & 0x1) == 0) {
						if ((subIndex < Bitmap.totalPages) && ((subIndex & mask) >= (Cpu.identifier * offset) ) && ((subIndex & mask) < (Cpu.identifier * offset + offset ))) {
						uint temp = subIndex & mask;
						//kprintfln!("CPU: {} Page_color: {}")(Cpu.identifier, temp);
							// mark it off as used
							*curPtr |= cast(ulong)(1UL << b);
							//kprintfln!("found: {} : {}")(subIndex, subIndex & color_shift);

							// return the page index
							return subIndex;
						}
						else if (subIndex >= Bitmap.totalPages) {
							//kprintfln!("foobar")();
							return 0xffffffffffffffffUL;
						}
					}
					tmpVal >>= 1;
					subIndex++;
				}
			}

			curIndex += 64;
			if (curIndex >= Bitmap.totalPages) {
				//kprintfln!("foobar2")();
				return 0xffffffffffffffffUL;
			}
			curPtr++;
		}

		return 0xffffffffffffffffUL;
	}
	
}
