MANDIR    = /usr/share/man/man8
MANFILE   = tagprotect.8
TARGET = ${MANDIR}/${MANFILE}

help:
	@echo man install
	@echo will install the man page
	@echo "    " ${MANFILE}
	@echo as 
	@echo "    " ${TARGET}

install:
	@mkdir    -p ${MANDIR};
	@/bin/cp -vf ${MANFILE} ${TARGET};
