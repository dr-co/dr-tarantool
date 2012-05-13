/* vim: set ft=c */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <tarantool/tnt.h>
#include <string.h>


static struct tnt_tuple* tmake_tuple( AV *t ) {
	int i;

	struct tnt_tuple *r = tnt_mem_alloc( sizeof( struct tnt_tuple ) );
	if ( !r )
		croak("Can not allocate memory");
	tnt_tuple_init( r );
	r->alloc = 1;

	for (i = 0; i <= av_len( t ); i++) {
		STRLEN size;
		char *data = SvPV( *av_fetch( t, i, 0 ), size );
		tnt_tuple_add( r, data, size );
	}
	return r;
}

static struct tnt_stream * tmake_buf(void) {
	struct tnt_stream *b = tnt_buf( NULL );
	if ( !b )
		croak("Can not allocate memory");

	return b;
}


static struct tnt_stream *tmake_oplist( AV *ops ) {
	int i;
	struct tnt_stream *b = tmake_buf();

	for (i = 0; i <= av_len( ops ); i++) {
		uint8_t opcode;

		SV *op = *av_fetch( ops, i, 0 );
		if (!SvROK(op) || SvTYPE( SvRV(op) ) != SVt_PVAV)
			croak("Wrong update operation format");
		AV *aop = (AV *)SvRV(op);

		int asize = av_len( aop ) + 1;
		if ( asize < 2 )
			croak("Too short operation argument list");

		unsigned fno = SvIV( *av_fetch( aop, 0, 0 ) );
		STRLEN size;
		char *opname = SvPV( *av_fetch( aop, 1, 0 ), size );


		/* delete */
		if ( strcmp(opname, "delete") == 0 ) {
			tnt_update_delete( b, fno );
			continue;
		}


		if (asize < 3)
			croak("Too short operation argument list");

		/* assign */
		if ( strcmp(opname, "set") == 0 ) {

			char *data = SvPV( *av_fetch( aop, 2, 0 ), size );
			tnt_update_assign( b, fno, data, size );
			continue;
		}

		/* insert */
		if ( strcmp(opname, "insert") == 0 ) {
			char *data = SvPV( *av_fetch( aop, 2, 0 ), size );
			tnt_update_insert( b, fno, data, size );
			continue;
		}


		/* arithmetic operations */
		if ( strcmp(opname, "add") == 0 ) {
			opcode = TNT_UPDATE_ADD;
			goto ARITH;
		}
		if ( strcmp(opname, "and") == 0 ) {
			opcode = TNT_UPDATE_AND;
			goto ARITH;
		}
		if ( strcmp(opname, "or") == 0 ) {
			opcode = TNT_UPDATE_OR;
			goto ARITH;
		}
		if ( strcmp(opname, "xor") == 0 ) {
			opcode = TNT_UPDATE_XOR;
			goto ARITH;
		}


		/* substr */
		if ( strcmp(opname, "substr") == 0 ) {
			if (asize < 5)
				croak("Too short argument list for substr");
			unsigned offset = SvIV( *av_fetch( aop, 2, 0 ) );
			unsigned length = SvIV( *av_fetch( aop, 3, 0 ) );
			char * data = SvPV( *av_fetch( aop, 4, 0 ), size );
			tnt_update_splice( b, fno, offset, length, data, size );
			continue;
		}

		{ /* unknown command */
			char err[512];
			snprintf(err, 512,
				"unknown update operation: `%s'",
				opname
			);
			croak(err);
		}

		ARITH: {
			tnt_update_arith(
				b, fno, opcode, SvIV( *av_fetch( aop, 2, 0 ) )
			);
			continue;
		}

	}

	return b;

}


MODULE = DR::Tarantool		PACKAGE = DR::Tarantool
PROTOTYPES: ENABLE

SV * _pkt_select( req_id, ns, idx, offset, limit, keys )
	unsigned req_id
	unsigned ns
	unsigned idx
	unsigned offset
	unsigned limit
	AV * keys


	CODE:
		int i;
		struct tnt_list list;
		tnt_list_init( &list );

		if ( ( list.count = av_len ( keys ) + 1 ) ) {
			list.list = tnt_mem_alloc(
				sizeof( struct tnt_list_ptr ) * list.count
			);


			if ( !list.list )
				return;

			for (i = 0; i < list.count; i++) {
				SV *t = *av_fetch( keys, i, 0 );
				if (!SvROK(t) || (SvTYPE(SvRV(t)) != SVt_PVAV))
					croak("keys must be ARRAYREF"
						" of ARRAYREF"
					);

				list.list[i].ptr = tmake_tuple( (AV *)SvRV(t) );
			}
		}

		struct tnt_stream *s = tmake_buf();
		tnt_stream_reqid( s, req_id );
		tnt_select( s, ns, idx, offset, limit, &list );
		tnt_list_free( &list );


		RETVAL = newSVpvn( TNT_SBUF_DATA(s), TNT_SBUF_SIZE(s) );
		tnt_stream_free( s );

	OUTPUT:
		RETVAL


SV * _pkt_ping( req_id )
	unsigned req_id

	CODE:
		struct tnt_stream *s = tmake_buf();
		tnt_stream_reqid( s, req_id );
		tnt_ping( s );
		RETVAL = newSVpvn( TNT_SBUF_DATA(s), TNT_SBUF_SIZE(s) );
		tnt_stream_free( s );
	OUTPUT:
		RETVAL

SV * _pkt_insert( req_id, ns, flags, tuple )
	unsigned req_id
	unsigned ns
	unsigned flags
	AV * tuple

	CODE:
		struct tnt_tuple *t = tmake_tuple( tuple );
		struct tnt_stream *s = tmake_buf();
		tnt_stream_reqid( s, req_id );
		tnt_insert( s, ns, flags, t );
		tnt_tuple_free( t );
		RETVAL = newSVpvn( TNT_SBUF_DATA( s ), TNT_SBUF_SIZE( s ) );
		tnt_stream_free( s );

	OUTPUT:
		RETVAL

SV * _pkt_update( req_id, ns, flags, tuple, operations )
	unsigned req_id
	unsigned ns
	unsigned flags
	AV *tuple
	AV *operations

	CODE:
		struct tnt_tuple *t = tmake_tuple( tuple );
		struct tnt_stream *s = tmake_buf();
		struct tnt_stream *ops = tmake_oplist( operations );

		tnt_stream_reqid( s, req_id );
		tnt_update( s, ns, flags, t, ops );
		tnt_tuple_free( t );

		RETVAL = newSVpvn( TNT_SBUF_DATA( s ), TNT_SBUF_SIZE( s ) );

		tnt_stream_free( ops );
		tnt_stream_free( s );


	OUTPUT:
		RETVAL

SV * _pkt_delete( req_id, ns, flags, tuple )
	unsigned req_id
	unsigned ns
	unsigned flags
	AV *tuple

	CODE:
		struct tnt_tuple *t = tmake_tuple( tuple );
		struct tnt_stream *s = tmake_buf();
		tnt_stream_reqid( s, req_id );
		tnt_delete( s, ns, flags, t );
		tnt_tuple_free( t );
		RETVAL = newSVpvn( TNT_SBUF_DATA( s ), TNT_SBUF_SIZE( s ) );
		tnt_stream_free( s );
	OUTPUT:
		RETVAL

SV * _pkt_call( req_id, flags, proc, tuple )
	unsigned req_id
	unsigned flags
	char *proc
	AV *tuple

	CODE:
		struct tnt_tuple *t = tmake_tuple( tuple );
		struct tnt_stream *s = tmake_buf();
		tnt_stream_reqid( s, req_id );
		tnt_call( s, flags, proc, t );
		tnt_tuple_free( t );
		RETVAL = newSVpvn( TNT_SBUF_DATA( s ), TNT_SBUF_SIZE( s ) );
		tnt_stream_free( s );
	OUTPUT:
		RETVAL
