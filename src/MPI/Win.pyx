cdef class Win:

    """
    Window
    """

    def __cinit__(self):
        self.ob_mpi = MPI_WIN_NULL

    def __dealloc__(self):
        cdef int ierr = 0
        ierr = _del_Win(&self.ob_mpi); CHKERR(ierr)

    def __richcmp__(Win self, Win other, int op):
        if   op == 2: return (self.ob_mpi == other.ob_mpi)
        elif op == 3: return (self.ob_mpi != other.ob_mpi)
        else: raise TypeError("only '==' and '!='")

    def __nonzero__(self):
        return self.ob_mpi != MPI_WIN_NULL

    def __bool__(self):
        return self.ob_mpi != MPI_WIN_NULL

    # [6.2] Initialization
    # --------------------

    # [6.2.1] Window Creation
    # -----------------------

    @classmethod
    def Create(cls, memory, int disp_unit=1, Info info=None, Intracomm comm=None):
        """
        Create an window object for one-sided communication
        """
        cdef void*    base = MPI_BOTTOM
        cdef MPI_Aint size = 0
        if memory is not None:
            memory = asmemory(memory, &base, &size)
        cdef MPI_Info cinfo = MPI_INFO_NULL
        if info is not None: cinfo = info.ob_mpi
        cdef MPI_Comm ccomm = MPI_COMM_SELF
        if comm is not None: ccomm = comm.ob_mpi
        #
        cdef Win win = cls()
        CHKERR( MPI_Win_create(base, size, disp_unit,
                               cinfo, ccomm, &win.ob_mpi) )
        # we are in charge or managing MPI errors
        CHKERR( MPI_Win_set_errhandler(
            win.ob_mpi, MPI_ERRORS_RETURN) )
        # old a reference to the object exposing memory
        win.ob_memory = memory
        # return the created window
        return win

    def Free(self):
        """
        Free a window
        """
        CHKERR( MPI_Win_free(&self.ob_mpi) )

    # [6.2.2] Window Attributes
    # -------------------------

    def Get_group(self):
        """
        Return a duplicate of the group of the
        communicator used to create the window
        """
        cdef Group group = Group()
        CHKERR( MPI_Win_get_group(self.ob_mpi, &group.ob_mpi) )
        return group

    property group:
        """window group"""
        def __get__(self):
            return self.Get_group()

    property attrs:
        "window attributes"
        def __get__(self):
            cdef MPI_Win win = self.ob_mpi
            cdef void *base = NULL, *pbase = NULL
            cdef MPI_Aint size = 0, *psize = NULL
            cdef int      disp = 0, *pdisp = NULL
            cdef int attr = MPI_KEYVAL_INVALID
            cdef int flag = 0
            #
            attr = MPI_WIN_BASE
            CHKERR( MPI_Win_get_attr(win, attr, &pbase, &flag) )
            if flag and pbase: base = pbase
            #
            attr = MPI_WIN_SIZE
            CHKERR( MPI_Win_get_attr(win, attr, &psize, &flag) )
            if flag and psize: size = psize[0]
            #
            attr = MPI_WIN_DISP_UNIT
            CHKERR( MPI_Win_get_attr(win, attr, &pdisp, &flag) )
            if flag and pdisp: disp = pdisp[0]
            #
            return (<MPI_Aint>base, size, disp)

    property memory:
        """window memory buffer"""
        def __get__(self):
            cdef MPI_Win win = self.ob_mpi
            cdef void *base = NULL, *pbase = NULL
            cdef MPI_Aint size = 0, *psize = NULL
            cdef int attr = MPI_KEYVAL_INVALID
            cdef int flag = 0
            #
            attr = MPI_WIN_BASE
            CHKERR( MPI_Win_get_attr(win, attr, &pbase, &flag) )
            if flag and pbase: base = pbase
            #
            attr = MPI_WIN_SIZE
            CHKERR( MPI_Win_get_attr(win, attr, &psize, &flag) )
            if flag and psize: size = psize[0]
            #
            return tomemory(base, size)

    # [6.3] Communication Calls
    # -------------------------

    # [6.3.1] Put
    # -----------

    def Put(self, origin, int target_rank, target=None):
        """
        Put data into a memory window on a remote process.
        """
        cdef message_rma msg = \
             message_rma_put(origin, target_rank, target)
        CHKERR( MPI_Put(msg.oaddr, msg.ocount, msg.otype,
                        target_rank,
                        msg.tdisp, msg.tcount, msg.ttype,
                        self.ob_mpi) )

    # [6.3.2] Get
    # -----------

    def Get(self, origin, int target_rank, target=None):
        """
        Get data from a memory window on a remote process.
        """
        cdef message_rma msg = \
             message_rma_get(origin, target_rank, target)
        CHKERR( MPI_Get(msg.oaddr, msg.ocount, msg.otype,
                        target_rank,
                        msg.tdisp, msg.tcount, msg.ttype,
                        self.ob_mpi) )

    # [6.3.4] Accumulate Functions
    # ----------------------------

    def Accumulate(self, origin, int target_rank,
                   target=None, Op op=None):
        """
        Accumulate data into the target process
        using remote memory access.
        """
        cdef message_rma msg = \
             message_rma_acc(origin, target_rank, target)
        cdef MPI_Op cop = MPI_SUM
        if op is not None: cop = (<Op?>op).ob_mpi
        CHKERR( MPI_Accumulate(msg.oaddr, msg.ocount, msg.otype,
                               target_rank,
                               msg.tdisp, msg.tcount, msg.ttype,
                               cop, self.ob_mpi) )

    # [6.4] Synchronization Calls
    # ---------------------------

    # [6.4.1] Fence
    # -------------

    def Fence(self, int assertion=0):
        """
        Perform an MPI fence synchronization on a window
        """
        CHKERR( MPI_Win_fence(assertion, self.ob_mpi) )

    # [6.4.2] General Active Target Synchronization
    # ---------------------------------------------

    def Start(self, Group group not None, int assertion=0):
        """
        Start an RMA access epoch for MPI
        """
        CHKERR( MPI_Win_start(group.ob_mpi, assertion, self.ob_mpi) )

    def Complete(self):
        """
        Completes an RMA operations begun after an `Win.Start()`
        """
        CHKERR( MPI_Win_complete(self.ob_mpi) )

    def Post(self, Group group not None, int assertion=0):
        """
        Start an RMA exposure epoch
        """
        CHKERR( MPI_Win_post(group.ob_mpi, assertion, self.ob_mpi) )

    def Wait(self):
        """
        Complete an RMA exposure epoch begun with `Win.Post()`
        """
        CHKERR( MPI_Win_wait(self.ob_mpi) )

    def Test(self):
        """
        Test whether an RMA exposure epoch has completed
        """
        cdef bint flag = 0
        CHKERR( MPI_Win_test(self.ob_mpi, &flag) )
        return flag

    # [6.4.3] Lock
    # ------------

    def Lock(self, int lock_type, int rank, int assertion=0):
        """
        Begin an RMA access epoch at the target process
        """
        CHKERR( MPI_Win_lock(lock_type, rank,
                             assertion, self.ob_mpi) )

    def Unlock(self, int rank):
        """
        Complete an RMA access epoch at the target process
        """
        CHKERR( MPI_Win_unlock(rank, self.ob_mpi) )

    # [6.6] Error Handling
    # --------------------

    def Get_errhandler(self):
        """
        Get the error handler for a window
        """
        cdef Errhandler errhandler = Errhandler()
        CHKERR( MPI_Win_get_errhandler(self.ob_mpi,
                                       &errhandler.ob_mpi) )
        return errhandler

    def Set_errhandler(self, Errhandler errhandler not None):
        """
        Set the error handler for a window
        """
        CHKERR( MPI_Win_set_errhandler(self.ob_mpi,
                                       errhandler.ob_mpi) )

    def Call_errhandler(self, int errorcode):
        """
        Call the error handler installed on a window
        """
        CHKERR( MPI_Win_call_errhandler(self.ob_mpi, errorcode) )


    # [8.4] Naming Objects
    # --------------------

    def Get_name(self):
        """
        Get the print name associated with the window
        """
        cdef char name[MPI_MAX_OBJECT_NAME+1]
        cdef int nlen = 0
        CHKERR( MPI_Win_get_name(self.ob_mpi, name, &nlen) )
        return tompistr(name, nlen)

    def Set_name(self, name):
        """
        Set the print name associated with the window
        """
        cdef char *cname = NULL
        name = asmpistr(name, &cname, NULL)
        CHKERR( MPI_Win_set_name(self.ob_mpi, cname) )

    property name:
        """window name"""
        def __get__(self):
            return self.Get_name()
        def __set__(self, value):
            self.Set_name(value)


# Predefined null window handle
WIN_NULL = _new_Win(MPI_WIN_NULL)


# Assertion modes
MODE_NOCHECK   = MPI_MODE_NOCHECK
MODE_NOSTORE   = MPI_MODE_NOSTORE
MODE_NOPUT     = MPI_MODE_NOPUT
MODE_NOPRECEDE = MPI_MODE_NOPRECEDE
MODE_NOSUCCEED = MPI_MODE_NOSUCCEED

# Lock types
LOCK_EXCLUSIVE = MPI_LOCK_EXCLUSIVE
LOCK_SHARED    = MPI_LOCK_SHARED