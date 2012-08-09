#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "pdl.h"
#include "pdlcore.h"

static Core* PDL;
static SV* CoreSV;

static void default_magic (pdl *p, size_t pa) {
	/* Zero the data pointers so that deletion doesn't screw with them. */
	p->data = 0;
	p->datasv = 0;
}

MODULE = PDL::Parallel::threads           PACKAGE = PDL::Parallel::threads

/* Integers (which can be cast to and from pointers) are easily shared using
 * threads::shared and a shared hash. This method provides a way to obtain
 * that most useful pointer. */
size_t
_get_pointer (piddle)
	pdl * piddle
	CODE:
		RETVAL = (size_t)(piddle);
	OUTPUT:
		RETVAL

/* Given the pointer value that was retrieved with _get_pointer, this method
 * builds a new piddle that is a thin copy of the old piddle. In particular,
 * it uses the exact same data and datasv pointers. */
pdl*
_wrap (data_pointer)
	size_t data_pointer
	CODE:
		pdl * old_pdl = (pdl*) data_pointer;	/* retrieve the parent piddle */
		pdl * new_pdl = PDL->pdlnew();			/* get a new container */
		
		/* Copy the important bits */
		new_pdl->state = old_pdl->state;
		new_pdl->datasv = old_pdl->datasv;
		new_pdl->data = old_pdl->data;
		new_pdl->datatype = old_pdl->datatype;
		
		/* Copy the dims; use the method rather than doing this by hand */
		PDL->setdims(new_pdl, old_pdl->dims, old_pdl->ndims);
		
		/* Tell the piddle that it doesn't really own the data */
		new_pdl->state |= PDL_DONTTOUCHDATA | PDL_ALLOCATED;
		PDL->add_deletedata_magic(new_pdl, default_magic, 0);
		
		RETVAL = new_pdl;
	OUTPUT:
		RETVAL

BOOT:
	perl_require_pv("PDL::Core");
	CoreSV = perl_get_sv("PDL::SHARE",FALSE);
	if (CoreSV==NULL)
		croak("Can't load PDL::Core module");
	PDL = INT2PTR(Core*, SvIV( CoreSV ));
	if (PDL->Version != PDL_CORE_VERSION)
		croak("[PDL->Version: %d PDL_CORE_VERSION: %d XS_VERSION: %s] PDL::Parallel::threads needs to be recompiled against the newly installed PDL", PDL->Version, PDL_CORE_VERSION, XS_VERSION);

