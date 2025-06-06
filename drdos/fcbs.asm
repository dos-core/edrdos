title 'FCB - DOS file system FCB support'
;    File              : $FCBS.ASM$
;
;    Description       :
;
;    Original Author   : DIGITAL RESEARCH
;
;    Last Edited By    : $CALDERA$
;
;-----------------------------------------------------------------------;
;    Copyright Work of Caldera, Inc. All Rights Reserved.
;      
;    THIS WORK IS A COPYRIGHT WORK AND CONTAINS CONFIDENTIAL,
;    PROPRIETARY AND TRADE SECRET INFORMATION OF CALDERA, INC.
;    ACCESS TO THIS WORK IS RESTRICTED TO (I) CALDERA, INC. EMPLOYEES
;    WHO HAVE A NEED TO KNOW TO PERFORM TASKS WITHIN THE SCOPE OF
;    THEIR ASSIGNMENTS AND (II) ENTITIES OTHER THAN CALDERA, INC. WHO
;    HAVE ACCEPTED THE CALDERA OPENDOS SOURCE LICENSE OR OTHER CALDERA LICENSE
;    AGREEMENTS. EXCEPT UNDER THE EXPRESS TERMS OF THE CALDERA LICENSE
;    AGREEMENT NO PART OF THIS WORK MAY BE USED, PRACTICED, PERFORMED,
;    COPIED, DISTRIBUTED, REVISED, MODIFIED, TRANSLATED, ABRIDGED,
;    CONDENSED, EXPANDED, COLLECTED, COMPILED, LINKED, RECAST,
;    TRANSFORMED OR ADAPTED WITHOUT THE PRIOR WRITTEN CONSENT OF
;    CALDERA, INC. ANY USE OR EXPLOITATION OF THIS WORK WITHOUT
;    AUTHORIZATION COULD SUBJECT THE PERPETRATOR TO CRIMINAL AND
;    CIVIL LIABILITY.
;-----------------------------------------------------------------------;
;
;    *** Current Edit History ***
;    *** End of Current Edit History ***
;    $Log$
;    FCBS.A86 1.10 93/11/11 15:38:14
;    Chart Master fix - fcb_readblk over > 64k is truncated to 64k and
;    error 2 (Segment boundry overlap) is returned
;    FCBS.A86 1.9 93/10/18 17:37:06
;    fix for >255 open files (PNW Server)
;    ENDLOG

PCMCODE	GROUP	BDOS_CODE
PCMDATA	GROUP	BDOS_DATA,PCMODE_DATA

ASSUME DS:PCMDATA

	.nolist
	include fdos.equ
	include msdos.equ
	include mserror.equ
	include doshndl.def	; DOS Handle Structures
	.list

BDOS_DATA	segment public word 'DATA'
BDOS_DATA	ends

BDOS_CODE	segment public byte 'CODE'

	extrn	ifn2dhndl:near
	extrn	parse_one:near
	extrn	fdos_entry:near

	Public	fdos_exit

;	TERMINATE CHILD (EXIT)

;	+----+----+
;	|    24   |
;	+----+----+

;	entry:
;	------
;	-none-

;	exit:
;	-----
;	-none-

; Close down all FCB handles associated with the current PSP
;
fdos_exit:
;---------
	push	ds
	push 	ss
	pop 	ds			; DS -> PCM_DSEG
	sub	ax,ax			; start with first DHNDL_
fdos_exit10:
	call	ifn2dhndl		; get DHNDL_
	 jc	fdos_exit40		; stop if we have run out
	mov	fcb_pb+2,ax		; we may close this IFN
	push	ax
	mov	cx,es:DHNDL_COUNT[bx]	; get the open count
	 jcxz	fdos_exit30		; skip if nothing to do
	mov	ax,current_psp		; get current PSP
	cmp	ax,es:DHNDL_PSP[bx]	; does it belong to this PSP
	 jne	fdos_exit30
	mov	ax,ss:machine_id	; get current process
    cmp ax,es:DHNDL_UID[bx] 
	 jne	fdos_exit30
	test	es:DHNDL_MODE[bx],DHM_FCB
	 jz	fdos_exit20		; skip close if not FCB
	push	es
	push	bx			; save the DHNDL
	mov	ax,MS_X_CLOSE
	call	fcb_fdos		; make the FDOS do the work
	pop	bx
	pop	es			; recover the DHNDL
fdos_exit20:
	mov	es:DHNDL_COUNT[bx],0	; always free the handle if it's ours
fdos_exit30:
	pop	ax
	inc	al			; onto next IFN
	 jnz	fdos_exit10
fdos_exit40:
	pop	ds
	ret





	Public	fdos_fcb
		
;	GENERIC FCB FUNCTION (FCB)

;	+----+----+----+----+----+----+----+----+
;	|    22   |       fcbadr      |  count  |
;	+----+----+----+----+----+----+----+----+
;	|  func   |
;	+----+----+

;	entry:
;	------
;	fcbadr:	FCB address
;	count:	multi-sector count for read/write
;	func:	FCB sub-function

;	exit:
;	-----
;	AX:	return code or error code ( < 0)

fdos_fcb:
;--------
	mov	bx,2[bp]		; BX -> parameter block
	mov	bx,8[bx]		; get subfunction code
	shl	bx,1			; make it word index
	sub	bl,15*WORD		; adjust to base address
	 jc	fcb_error		; reject if too low
	cmp	bl,FCB_MAX1		; is it in 1st block
	 jb	fdos_fcb10
	sub	bl,(33-24)*WORD		; adjust for gap
	 jc	fcb_error
	cmp	bl,FCB_MAX2		; is it in 2nd block
	 jb	fdos_fcb10
	sub	bl,(39-37)*WORD		; adjust for gap
	 jc	fcb_error
fdos_fcb10:
	cmp	bx,FCB_MAX3		; check the range
	 jae	fcb_error		; skip if invalid function
	jmp	fcb_table[bx]		; call the right function

fcb_error:
	mov	bx,ED_FUNCTION
	ret

fcb_table	dw	fcb_open	; 15-open file
		dw	fcb_close	; 16-close file
		dw	fcb_first	; 17-find first
		dw	fcb_next	; 18-find next
		dw	fcb_delete	; 19-delete file
		dw	fcb_read	; 20-read from file
		dw	fcb_write	; 21-write to file
		dw	fcb_make	; 22-make file
		dw	fcb_rename	; 23-rename file
FCB_MAX1	equ	(offset $ - offset fcb_table)
		dw	fcb_readrand	; 33-read from file
		dw	fcb_writerand	; 34-write to file
		dw	fcb_size	; 35-compute file size
		dw	fcb_setrecord	; 36-set relative record
FCB_MAX2	equ	(offset $ - offset fcb_table)
		dw	fcb_readblk	; 39-read from file
		dw	fcb_writeblk	; 40-write to file
FCB_MAX3	equ	(offset $ - offset fcb_table)

fcb_make:
;--------
	call	fcb_path_prep		; build pathname
	mov	ax,MS_X_CREAT
	jmp	fcb_open_make_common

fcb_open:
;--------
	call	fcb_path_prep		; build pathname
	mov	ax,MS_X_OPEN
fcb_open_make_common:
	mov	fcb_pb+6,DHM_RW+DHM_FCB	; open as an FCB for read/write
	call	fcb_fdos		; lets try and open the file
	 jnc	fcb_open10		; skip if we can't
	ret
fcb_open10:
	call	ifn2dhndl		; ES:BX -> DHNDL_ we have opened
	push	ds
	push 	es
	push 	bx			; save DHNDL_
	call	fcb_point		; ES:BX = FCB
	pop 	si
	pop 	ds			; DS:SI -> DHNDL_
	mov	es:MSF_IFN[bx],al	; store IFN away
	mov	es:MSF_BLOCK[bx],0	; current block number
	mov	es:MSF_RECSIZE[bx],128	; current logical record size
	call	fcb_update		; update misc changing fields
	mov	ax,ds:DHNDL_DEVOFF[si]
	mov	es:word ptr MSF_DEVPTR[bx],ax
	mov	ax,ds:DHNDL_DEVSEG[si]
	mov	es:word ptr MSF_DEVPTR+2[bx],ax
	mov	ax,ds:DHNDL_BLK1[si]
	mov	es:MSF_BLOCK1[bx],ax
	mov	al,ds:DHNDL_ATTR[si]
	mov	es:MSF_IOCTL[bx],al
	mov	al,es:MSF_DRIVE[bx]	; get drive from FCB
	dec	al			; was absolute drive specified ?
	 jns	fcb_open20		; if so use it
	mov	al,ss:current_dsk	; else use default drive
fcb_open20:
	inc	al			; make drive 1 rather than 0 based
	mov	es:MSF_DRIVE[bx],al	; drive code
if 0
	test	ds:DHNDL_DATRB[si],DA_VOLUME
else
	test	ss:fcb_pb+8,DA_VOLUME
endif
	pop	ds
	 jnz	fcb_close		; don't leave VOL label's open
	xor	bx,bx			; no errors !
	ret


fcb_update:
;----------
; On Entry:
;	DS:SI -> DHNDL_
;	ES:BX -> FCB
; On Exit:
;	DATE/TIME/SIZE/DBLK/DCNT fields updated
;
	mov	ax,ds:DHNDL_TIME[si]
	mov	es:MSF_TIME[bx],ax
	mov	ax,ds:DHNDL_DATE[si]
	mov	es:MSF_DATE[bx],ax
	mov	ax,ds:DHNDL_SIZELO[si]
	mov	es:MSF_SIZE[bx],ax
	mov	ax,ds:DHNDL_SIZEHI[si]
	mov	es:MSF_SIZE+2[bx],ax
	mov	ax,ds:DHNDL_DBLK[si]
	mov	es:MSF_DBLK[bx],ax
	mov	al,ds:DHNDL_DCNTLO[si]
	mov	ah,ds:DHNDL_DCNTHI[si]
	mov	es:MSF_DCNT[bx],ax
	ret

fcb_close:
;---------
; close file (DOS function 10h)
	call	fcb_point		; ES:BX -> FCB
	mov	al,0FFh
	cmp	al,es:MSF_IFN[bx]	; is it a multiple close ?
	 je	fcb_fdos_common10	;  don't re-open for this...
	call	fcb_handle_vfy		; verify we have a sensible handle
	mov	es:MSF_IFN[bx],al	; mark FCB as closed (it will be)
	mov	ax,MS_X_CLOSE		; now close it
;	jmp	fcb_fdos_common

fcb_fdos_common:
;---------------
	call	fcb_fdos		; make the FDOS do the work
	 jc	fcb_fdos_common20	; return any error codes
fcb_fdos_common10:
	xor	bx,bx			; else return zero
fcb_fdos_common20:
	ret



fcb_rename:
;----------
	call	fcb_path_prep
	call	fcb_path2_prep
	mov	ax,MS_X_RENAME		; it's a rename
	jmp	fcb_fdos_common

fcb_delete:
;----------
	call	fcb_path_prep
	mov	ax,MS_X_UNLINK		; it's a delete
	jmp	fcb_fdos_common


fcb_first:
;---------
	call	fcb_path_prep		; prepare pathname
	mov	ax,MS_X_FIRST		; we want to search 1st
	jmp	fcb_search_common

fcb_next:
;--------
	call	fcb_restore_search_state
	mov	ax,MS_X_NEXT
fcb_search_common:
	call	fcb_search		; 0 of OK, otherwise ED_..
	 jc	fcb_search_common10
	call	fcb_save_search_state	; save sucessful state
	xor	bx,bx			; return code in BX
fcb_search_common10:
	ret


fcb_setrecord:
;-------------
	call	fcb_point		; ES:BX -> FCB
	mov	ax,128			; multiply current block by 128
	mul	es:MSF_BLOCK[bx]	;  to give current record number
	xor	cx,cx
	mov	cl,es:MSF_CR[bx]	; Add in the current record
	add	ax,cx			;  to DX:AX to give the
	adc	dx,0			;  relative record
	mov	es:MSF_RR[bx],ax	; save the result
	mov	es:MSF_RR2[bx],dl
	xor	bx,bx			; we did OK
	ret

fcb_write:
;---------
	mov	ax,MS_X_WRITE		; make it a write
	jmp	fcb_seq_rw

fcb_read:
;--------
	mov	ax,MS_X_READ		; make it a read
fcb_seq_rw:
	call	fcb_handle_vfy		; verify we have a sensible handle
	push	ax			; save the operation
	call	fcb_get_count		; AX = bytes to read
	push	ax			; save byte count
	call	fcb_seek_seq		; Seek to position in the file
	pop	cx			; recover byte to xfer
	pop	ax			;  and the Operation Code
	 jc	fcb_seq_rw10
	call	fcb_rw			; do the Op
	 jc	fcb_seq_rw10
	push	bx			; save the error code
	call	fcb_update_seq		; update FCB filepos
	pop	bx			; recover error
fcb_seq_rw10:
	ret

fcb_rw:
; On Entry:
;	AX = operation code
;	CX = count
;	fcb_pb+2 = IFN
; On Exit:
;	BX = error code
	les	dx,ss:dword ptr dma_offset
	add	cx,dx			; see if we overflow
	 jc	fcb_rw20
	sub	cx,dx			; count back to normal
	push	cx			; save target count
	mov	fcb_pb+4,dx
	mov	fcb_pb+6,es		; setup buffer address
	mov	fcb_pb+8,cx		;  and target count
	call	fcb_fdos		; ask the FDOS to do the read/write
	 jc	fcb_rw10		; we got a real error...
	push	ds
	push	es
	mov	ax,fcb_pb+2		; get IFN
	call	ifn2dhndl		; ES:BX -> DHNDL_ we have open
	push 	es
	push 	bx			; save DHNDL_
	call	fcb_point		; ES:BX = FCB
	pop 	si
	pop 	ds			; DS:SI -> DHNDL_
	call	fcb_update		; update file size/time-stamp
	pop	es
	pop	ds
	pop	ax			; recover target count
	mov	cx,fcb_pb+8		; we xfered this much
	cmp	cx,ax			; did we xfer enough
	 jb	fcb_rw30		; nope..
	xor	bx,bx			; xfer went OK
	ret

fcb_rw10:
	pop	ax			; discard target count
	ret

fcb_rw20:
; Our DTA is too small - return 2
	mov	bx,2			; indicate the DTA is too small
;	stc				; error - don't update FCB
	ret

fcb_rw30:
; We have some form of EOF - lets look into it
	call	fcb_point		; ES:BX = FCB
	mov	bx,es:MSF_RECSIZE[bx]	; BX = record size
	mov	ax,cx
	xor	dx,dx			; DX:AX = bytes xfer'd
	div	bx			; did we xfer a complete
	test	dx,dx			;  number of records ?
	 jz	fcb_rw40		;  if so return 1
; Partial data was read - fill out with zero's and return 3
	inc	ax			; allow for incomplete record
	push	ax			; save rounded up xfer count
	les	di,ss:dword ptr dma_offset
	add	di,cx			; point to 1st byte after xfer
	mov	cx,bx			; this many in a record
	sub	cx,dx			; so this many weren't xfer'd
	xor	ax,ax			; fill them with zero's
	rep	stosb			; zap the bytes we didn't xfer to
	pop	ax			; recover xfer count
	mul	bx			;  and work out # bytes xfered
	xchg	ax,cx			; return bytes in CX
	mov	bx,3			; indicate EOF (partial read)
;	clc				; update FCB
	ret
		
fcb_rw40:
; No Data was xfered - return 1
	mov	bx,1			; indicate EOF (no data read)
;	clc				; update FCB
	ret

fcb_writerand:
;-------------
	mov	ax,MS_X_WRITE		; make it a write
	jmp	fcb_random_rw

fcb_readrand:
;------------
	mov	ax,MS_X_READ		; make it a read
fcb_random_rw:
	call	fcb_handle_vfy		; check the handle is OK
	push	ax			; save the code
	call	fcb_get_count		; AX = bytes to read
	push	ax			; save byte count
	xor	cx,cx			; cause update of seq posn from
	call	fcb_update_rr		;  random record position
	call	fcb_seek_rr		; Seek to position in the file
	pop	cx			; recover byte to xfer
	pop	ax			;  and the Operation Code
	 jc	fcb_random_rw10
	call	fcb_rw			; do the Op
fcb_random_rw10:
	ret
	
		
fcb_writeblk:
;------------
	mov	ax,MS_X_WRITE		; make it a write
	jmp	fcb_block_rw

fcb_readblk:
;-----------
	mov	ax,MS_X_READ		; make it a read
fcb_block_rw:
	call	fcb_handle_vfy		; check the handle is OK
	push	ax			; save the code
	call	fcb_get_count		; AX = bytes per record, CX = # records
	xchg	ax,cx			; CX = bytes per record
	mul	cx			; AX = bytes to xfer
	test	dx,dx			; more than 64K ?
	 jz	fcb_block_rw10		; then we should truncate it
	mov	ax,15			; AX = handy mask
	cwd				; DX = 0
	and	ax,ss:dma_offset	; get dma offset for para
	not	ax			; DX/AX = maximum bytes we can xfer
	div	cx			; AX = maximum blocks we can xfer
	mul	cx			; AX = bytes to xfer (now < 64K)
fcb_block_rw10:	
	push	ax			; save byte count
	call	fcb_seek_rr		; Seek to position in the file
	pop	cx			; recover byte to xfer
	pop	ax			;  and the Operation Code
	 jc	fcb_block_rw20
	call	fcb_rw			; do the Op
	 jc	fcb_block_rw20
	push	bx			; save the error code
	call	fcb_update_rr		; update FCB filepos, get records xferd
	mov	bx,2[bp]		; BX -> parameter block
	xchg	cx,6[bx]		; update amount xfered
	sub	cx,6[bx]		; CX = # we didn't xfer (normally 0)
	pop	bx			; recover (possible) error
	 jcxz	fcb_block_rw20		; skip if we read all we wanted to
	test	bx,bx			; did we have a partial read for
	 jnz	fcb_block_rw20		;  a reason like EOF ?
	mov	bx,2			; no, we must have truncated it
fcb_block_rw20:
	ret
	
		
fcb_size:
;--------
	call	fcb_path_prep
	mov	ax,MS_X_CHMOD		; it's a get info
	mov	fcb_pb+6,0
	call	fcb_fdos
	 jc	fcb_size40
	call	fcb_point		; ES:BX = FCB
	mov	cx,es:MSF_RECSIZE[bx]	; get the record size
	test	cx,cx			; is it non-zero ?
	 jnz	fcb_size10		;  if not
	mov	cx,128			;  make it 128 bytes
fcb_size10:
	mov	ax,fcb_pb+10
	mov	dx,fcb_pb+12		; DX:AX = file length in bytes
	call	div_32			; DX:AX = file length in records
	 jcxz	fcb_size20		; was there an overflow
	add	ax,1
	adc	dx,0			; include an extra record
fcb_size20:
	call	fcb_point		; ES:BX = FCB
	mov	es:MSF_RR[bx],ax	; low word of size
	mov	es:MSF_RR2[bx],dl	; hi byte of size
	cmp	es:MSF_RECSIZE[bx],64	; if record size < 64 bytes
	 jae	fcb_size30		;  then we use a 4 byte
	mov	es:MSF_RR2+1[bx],dh	;  random record position
fcb_size30:
	xor	bx,bx			; good return
fcb_size40:
	ret


; Utility FCB subroutines
;========================

fcb_handle_vfy:
;--------------
; Verify FCB is valid and open, do not return if it isn't
; nb. Called with nothing on stack
;
; On Entry:
;	FCB address in parameter block
; On Exit:
;	AX preserved
;	ES:BX -> FCB (skipping EXT bit if present)
;	fcb_pb+2 = IFN of handle
;	On Error - blow away caller and return error in BX
;

; DEBUG - on reopen we could do more checks to ensure we are re-opening the
; same file
	push	ax
	call	fcb_point
	cmp	es:MSF_RECSIZE[bx],0
	 jne	fcb_handle_vfy10
	mov	es:MSF_RECSIZE[bx],128
fcb_handle_vfy10:
	mov	al,es:MSF_IFN[bx]	; get IFN
	call	ifn2dhndl		; ES:BX -> DHNDL_
	 jc	fcb_handle_vfy20	; it must be a valid IFN
	test	es:DHNDL_MODE[bx],DHM_FCB
	 jz	fcb_handle_vfy20	; it must be an FCB..
	cmp	es:DHNDL_COUNT[bx],0
	 jne	fcb_handle_vfy30	; it must also be open..
fcb_handle_vfy20:
	call	fcb_point
	push	es:MSF_RECSIZE[bx]	; save current record size
	push	es:MSF_BLOCK[bx]	; save current block number
	push 	es
	push 	bx
	call	fcb_open		; try to re-open the file
	pop 	bx
	pop 	es			; point back at FCB
	pop	es:MSF_BLOCK[bx]	; restore current block number
	pop	es:MSF_RECSIZE[bx]	; restore record size
	 jc	fcb_handle_err
	mov	al,es:MSF_IFN[bx]	; get new IFN
fcb_handle_vfy30:
	xor	ah,ah
	mov	fcb_pb+2,ax		; set parameter block accordingly
	call	fcb_point		; ES:BX -> MSF_
	pop	ax
	clc
	ret

fcb_handle_err:
	add	sp,2*WORD		; discard AX and near return address
	cmp	ax,ED_HANDLE		; if we have run out of handles then
	 jne	fcb_handle_err10	;  say no FCB's, else return error
	mov	ax,ED_NOFCBS
fcb_handle_err10:
	xchg	ax,bx			; error code in BX
	stc
	ret


fcb_path2_prep:
;--------------
; On Entry:
;	FCB address in parameter block
; On Exit:
;	ES:BX -> FCB (skipping EXT bit if present)
;	fcb_pb+6/8 -> unparse name from FCB
;
	call	fcb_point		; point at the FCB
	mov	al,es:MSF_DRIVE[bx]	; get drive
	add	bx,16			; point at 2nd name in FCB
	mov	di,offset fcb_path2
	mov	fcb_pb+10,di
	mov	fcb_pb+12,ds		; point at buffer we want
	jmp	fcb_path_prep_common

fcb_path_prep:
;-------------
; On Entry:
;	FCB address in parameter block
; On Exit:
;	ES:BX -> FCB (skipping EXT bit if present)
;	fcb_pb+2/4 -> unparse name from FCB
;
	xor	ax,ax			; assume no attribute
	mov	bx,2[bp]		; BX -> parameter block
	les	bx,2[bx]		; ES:BX -> FCB
	cmp	es:MSF_EXTFLG[bx],0ffh	; is it an extended FCB
	 jne	fcb_path_prep10
	or	al,es:MSF_ATTRIB[bx]	; we can use file mode from XFCB
	add	bx,7			; skip EXT bit of FCB
fcb_path_prep10:
	mov	fcb_pb+8,ax		; remember the attribute
	mov	al,es:MSF_DRIVE[bx]	; get drive
	mov	di,offset fcb_path
	mov	fcb_pb+2,di
	mov	fcb_pb+4,ds		; point at buffer we want
fcb_path_prep_common:
	dec	al			; 0 = default drive
	 jns	fcb_path_prep20
	mov	al,current_dsk		; use default drive
fcb_path_prep20:
	push	ds
	push 	ds
	push 	es
	pop 	ds
	pop 	es			; ES:DI -> name buffer
	add	al,'A'			; make drive ASCII
	stosb
	mov	al,':'
	stosb				; now we have 'd:'
	lea	si,MSF_NAME[bx]		; DS:SI -> source name
	movsw
	movsw
	movsw
	movsw				; copy the name leaving spaces intact
	mov	al,'.'
	stosb
	movsw
	movsb				; copy the extention
	pop	ds
;	jmp	fcb_point		; point ES:BX at FCB again


fcb_point:
;---------
; On Entry:
;	FCB address in parameter block
; On Exit:
;	ES:BX -> FCB (skipping EXT bit if present)
;	(All other regs preserved)
;
	mov	bx,2[bp]		; BX -> parameter block
	les	bx,2[bx]		; ES:BX -> FCB
	cmp	es:MSF_EXTFLG[bx],0ffh	; is it an extended FCB
	 jne	fcb_point10
	add	bx,7			; skip EXT bit of FCB
fcb_point10:
	ret

fcb_get_count:
;-------------
; On Entry:
;	none
; On Exit:
;	AX = bytes per record
;	CX = callers CX count
;	All regs fair game
;
	call	fcb_point		; ES:BX -> FCB
	mov	si,2[bp]		; SI -> parameter block
	mov	cx,6[si]		; CX = count
	mov	ax,es:MSF_RECSIZE[bx]	; get record size
	ret

fcb_update_seq:
;--------------
; On Entry:
;	CX = byte count actually transferred
; On Exit:
;	CX = record count transferred
;	All other regs fair game
;	CR/BLOCK updated with new value
;
	mov	ax,cx
	xor	dx,dx			; DX:AX = byte count transfered
	call	fcb_point		; ES:BX -> FCB
	div	es:MSF_RECSIZE[bx]	; make records xfered
	push	ax			; save records xfered
	xchg	ax,cx			; also in CX for later
	mov	ax,128
	mul	es:MSF_BLOCK[bx]	; DX:AX = record of block
	add	ax,cx
	adc	dx,0			; add in amount just xfered
	mov	cl,es:MSF_CR[bx]
	xor	ch,ch			; now add in CR as a word
	add	ax,cx
	adc	dx,0			; DX:AX = record
	mov	dh,dl			; DH:AX = record for common code
	jmp	fcb_update_common


fcb_update_rr:
;-------------
; On Entry:
;	CX = byte count actually transferred
; On Exit:
;	CX = record count transferred
;	All other regs fair game
;	Random Record and CR/BLOCK updated with new value
;
	xchg	ax,cx
	xor	dx,dx			; DX:AX = byte count transfered
	call	fcb_point		; ES:BX -> FCB
	div	es:MSF_RECSIZE[bx]	; make records xfered
	push	ax			; save records xfered
	add	es:MSF_RR[bx],ax	; update the RR field
	adc	es:MSF_RR2[bx],0	;  and the overflow
	mov	ax,es:MSF_RR[bx]	; get low part of RR
	mov	dh,es:MSF_RR2[bx]	;  and the hi part
fcb_update_common:
	mov	dl,ah			; DX will be block number
	shl	al,1			; get top bit of CR into CY
	adc	dx,dx			; then into DX
	shr	al,1			; AL = CR (remember mod 128)
	mov	es:MSF_CR[bx],al	; set the CR field
	mov	es:MSF_BLOCK[bx],dx	;  and the block field
	pop	cx			; recover records xfered
	ret


fcb_seek_seq:
;------------
; Seek to position in file indicated by the RR position
; On Entry:
;	ES:BX -> FCB_
; On Exit:
;	CY clear if no problem, fcb_pb+2=IFN
;	else
;	CY set, AX = BX = error code
;	All other regs fair game
;
	call	fcb_point		; ES:BX -> FCB_
	mov	ax,128
	mul	es:MSF_BLOCK[bx]	; get record in DX:AX
	mov	cl,es:MSF_CR[bx]
	xor	ch,ch
	add	ax,cx			; add in CR
	adc	dx,0			; so DX:AX is really the record
	push	ax			; save low word of record
	mov	ax,dx
	mul	es:MSF_RECSIZE[bx]	; DX:AX = byte offset in file/10000h
	mov	cx,ax			; save the important word
	pop	ax			; recover low word of record
	jmp	fcb_seek_common

fcb_seek_rr:
;-----------
; Seek to position in file indicated by the RR position
; On Entry:
;	ES:BX -> FCB_
; On Exit:
;	CY clear if no problem, fcb_pb+2=IFN
;	else
;	CY set, AX = BX = error code
;	All other regs fair game
;
	call	fcb_point		; ES:BX -> FCB_
	mov	al,es:MSF_RR2[bx]
	xor	ah,ah
	mul	es:MSF_RECSIZE[bx]	; DX:AX = byte offset in file/10000h
	mov	cx,ax			; save the important word
	mov	ax,es:MSF_RR[bx]
fcb_seek_common:
	mul	es:MSF_RECSIZE[bx]	; DX:AX = byte offset in file
	add	dx,cx			; add the two bits together
	mov	fcb_pb+4,ax
	mov	fcb_pb+6,dx		; save position
	mov	fcb_pb+8,0		; seek from start
	xor	ax,ax
	mov	al,es:MSF_IFN[bx]	; AX = IFN
	mov	fcb_pb+2,ax		; save IFN
	mov	ax,MS_X_LSEEK
	jmp	fcb_fdos		; try and seek to this position


fcb_search:
;----------
; On Entry:
;	AX = operation to perform
; On Exit:
;	AX = 0, or ED_ error code (CY set if error)
	push	dma_offset
	push	dma_segment
	mov	dma_offset,offset fcb_search_buf
	mov	dma_segment,ds
	call	fcb_fdos			; do the search
	pop	dma_segment
	pop	dma_offset
	test	ax,ax				; was there an error
	stc					; assume there was
	 js	fcb_search10			; return the error
	xor	ax,ax				; no problems
fcb_search10:
	ret

fcb_save_search_state:
;---------------------
; On entry DS=PCMODE
	
	call	fcb_point
	lea	di,MSF_NAME[bx]		; ES:DI -> FCB name
	mov	si,offset fcb_search_buf
	lodsb				; get 1st byte = drive info
	mov	cx,20/WORD		; copy 20 bytes to FCB
	rep	movsw			; (the rest of the search template)
	stosb				; drive info byte follow them
	
	les	di,dword ptr dma_offset	; ES:DI -> search state in DMA address
	mov	si,2[bp]		; SI -> parameter block
	lds	si,2[si]		; DS:SI -> FCB_
	cmp	ds:MSF_EXTFLG[si],0ffh	; extended FCB ?
	 jne	fcb_sss10
	mov	cx,7			; copy extended FCB portions too
	rep	movsb			; we have copied up to name
fcb_sss10:
	stosb				; save drive byte info
	push	di
	mov	al,' '			; space fill name
	mov	cx,11
	rep	stosb			; all blanks now
	pop	di
	push 	ss
	pop 	ds			; DS:SI -> pathname
	mov	si,offset fcb_search_buf+1Eh

	push	di			; unparse knowing name is good
	mov	cx,8			; length of name field
fcb_sss20:		 
	lodsb				; treat '.' and '..' specially
	cmp	al,'.'			; is either possible ?
	 jne	fcb_sss30		; no, continue as normal
	stosb				; copy the '.'
	loop	fcb_sss20		; go around for another '.'
	jmp	fcb_sss40		; this name is rubbish!!
fcb_sss30:
	dec	si			; forget the non '.'
	call	parse_one		; parse just the name
fcb_sss40:
	pop	di
	add	di,8			; di -> fcb ext field
	cmp	al,'.'			; do we have an extention ?
	 jne	fcb_sss50
	mov	cx,3			; length of ext field
	push	di
	call	parse_one		; parse just extension
	pop	di
fcb_sss50:
	add	di,3			; di -> rest of fcb
	mov	si,offset fcb_search_buf+15h
	movsb				; copy the attribute field
	xor	ax,ax
;	mov	cx,10/WORD
	mov	cx,8/WORD
	rep	stosw			; 10 bytes of zeros
	mov	ax,word ptr srch_buf+21+DBLOCK1H
	stosw				; high word of 1st block
	movsw				; copy time
	movsw				; copy date
	mov	ax,word ptr srch_buf+21+DBLOCK1
	stosw				; 1st block
	movsw
	movsw				; copy filesize
	ret

fcb_restore_search_state:
;------------------------
; On entry DS=PCMODE
	push	ds
	call	fcb_point		; ES:BX -> FCB_
	push 	es
	push 	ds
	pop 	es
	pop 	ds			; swap DS/ES
	mov	di,offset fcb_search_buf+1
					; ES:DI -> internal state
	lea	si,1[bx]		; DS:SI -> FCB+1
	mov	cx,10
	rep	movsw			; copy info from FCB
	lodsb				; get "drive" info
	mov	es:fcb_search_buf,al	; it's the 1st byte in the srch state
	pop	ds
	ret

fcb_fdos:
;--------
; Make an FDOS call (NB. We don't have MX here, so it's OK)
; Set top bit of remote_call flag so we use IFN's not XFN's
; On Entry:
;	AX = FDOS operation
;	fcb_pb -> FDOS parameter block
; On Exit:
;	As FDOS call
;
	mov	fcb_pb,ax		; save operation type
	or	remote_call,DHM_FCB	; forget about PSP during FCB call
	mov	dx,offset fcb_pb	; DS:DX -> parameter block
	push	ds
	push	bp
	call	fdos_entry		; call the FDOS
	pop	bp
	pop	ds
	and	remote_call,(not DHM_FCB) and 0ffffh	; FCB operation over
	cmp	ax,ED_LASTERROR
	cmc				; CY set if an error occurred
	ret

div_32:
;	Entry:	DX,AX = long dividend
;		CX = word divisor
;	Exit:	DX,AX = long result
;		CX = remainder

	jcxz	div0			; divide by 0
	cmp	cx,1
	 je	div1			; divide by 1
	push	di
	push	bx
	xor	bx,bx			; BX = 0
	xchg	ax,bx			; low word in BX, AX = 0
	xchg	ax,dx			; high word in DX:AX
	push	ax			; save high word
	div	cx			; divide high part
	mov	di,ax			; save result
	mul	cx			; AX = even divisor part
	pop	dx			; old high in DX
	sub	dx,ax			; eliminate even part
	xchg	ax,bx			; AX = low word
	div	cx			; low part in AX
	mov	cx,dx			; CX = remainder
	mov	dx,di			; high result in DX
	pop	bx
	pop	di
	ret

div0:
	mov	ax,-1
	mov	dx,ax
	ret
div1:
	dec	cx			; CX = remainder = 0
	ret

BDOS_CODE	ends

PCMODE_DATA	segment public word 'DATA'

extrn	fcb_pb:word
extrn	fcb_path:byte
extrn	fcb_path2:byte
extrn	fcb_search_buf:byte

extrn	current_dsk:byte
extrn	current_psp:word
extrn	dma_offset:word
extrn	dma_segment:word
extrn	machine_id:word
extrn	remote_call:word
extrn	srch_buf:byte

PCMODE_DATA	ends

end
