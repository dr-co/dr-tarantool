/* vim: set ft=c */
/*

 Copyright (C) 2011 Dmitry E. Oboukhov <unera@debian.org>
 Copyright (C) 2011 Roman V. Nikolaev <rshadow@rambler.ru>

 This program is free software, you can redistribute it and/or
 modify it under the terms of the Artistic License.

*/
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
			if (asize < 4)
				croak("Too short argument list for substr");
			unsigned offset = SvIV( *av_fetch( aop, 2, 0 ) );
			unsigned length = SvIV( *av_fetch( aop, 3, 0 ) );
			char * data;
			if ( asize > 4 && SvOK( *av_fetch( aop, 4, 0 ) ) ) {
			    data = SvPV( *av_fetch( aop, 4, 0 ), size );
			} else {
			    data = "";
			    size = 0;
                        }
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
		        unsigned long long v = 0;
			char *data = SvPV( *av_fetch( aop, 2, 0 ), size );
			if (sizeof(v) < size)
			    size = sizeof(v);
			memcpy(&v, data, size); 
			tnt_update_arith( b, fno, opcode, v );
			continue;
		}

	}

	return b;

}

static void hash_ssave(HV *h, const char *k, const char *v) {
	hv_store( h, k, strlen(k), newSVpvn( v, strlen(v) ), 0 );
}

static void hash_isave(HV *h, const char *k, uint32_t v) {
	hv_store( h, k, strlen(k), newSViv( v ), 0 );
}

static AV * extract_tuples(struct tnt_reply *r) {
	struct tnt_iter it;
	tnt_iter_list(&it, TNT_REPLY_LIST(r));
	AV *res = newAV();
	sv_2mortal((SV *)res);

	while (tnt_next(&it)) {
		struct tnt_iter ifl;
		struct tnt_tuple *tu = TNT_ILIST_TUPLE(&it);
		tnt_iter(&ifl, tu);
		AV *t = newAV();
		while (tnt_next(&ifl)) {
			char *data = TNT_IFIELD_DATA(&ifl);
			uint32_t size = TNT_IFIELD_SIZE(&ifl);
			av_push(t, newSVpvn(data, size));
		}
		av_push(res, newRV_noinc((SV *) t));

		tnt_iter_free(&ifl);
	}

	tnt_iter_free(&it);
	return res;
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

SV * _pkt_call_lua( req_id, flags, proc, tuple )
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



HV * _pkt_parse_response( response )
	SV *response

	INIT:
		RETVAL = newHV();
		sv_2mortal((SV *)RETVAL);

	CODE:
		if ( !SvOK(response) )
			croak( "response is undefined" );
		STRLEN size;
		char *data = SvPV( response, size );
		struct tnt_reply reply;
		tnt_reply_init( &reply );
		size_t offset = 0;
		int cnt = tnt_reply( &reply, data, size, &offset );
		int i, j;

		if ( cnt < 0 ) {
			hash_ssave(RETVAL, "status", "fatal");
			hash_ssave(RETVAL,
			    "errstr", "Can't parse server response");
		} else if ( cnt > 0 ) {
			hash_ssave(RETVAL, "status", "buffer");
			hash_ssave(RETVAL, "errstr", "Input data too short");
		} else {
			hash_isave(RETVAL, "code", reply.code );
			hash_isave(RETVAL, "req_id", reply.reqid );
        		hash_isave(RETVAL, "type", reply.op );
        		hash_isave(RETVAL, "count", reply.count);
        		if (reply.code) {
        		    hash_ssave(RETVAL, "errstr", reply.error );
			    hash_ssave(RETVAL, "status", "error");

                        } else {
			    hash_ssave(RETVAL, "status", "ok");
                            AV *tuples = extract_tuples( &reply );
                            hv_store(RETVAL, "tuples",
                            	6, newRV((SV *)tuples), 0);
                        }
		}
		tnt_reply_free( &reply );

	OUTPUT:
		RETVAL


unsigned _op_insert()
	CODE:
		RETVAL = TNT_OP_INSERT;
	OUTPUT:
		RETVAL

unsigned _op_select()
	CODE:
		RETVAL = TNT_OP_SELECT;
	OUTPUT:
		RETVAL

unsigned _op_update()
	CODE:
		RETVAL = TNT_OP_UPDATE;
	OUTPUT:
		RETVAL

unsigned _op_delete()
	CODE:
		RETVAL = TNT_OP_DELETE;
	OUTPUT:
		RETVAL

unsigned _op_call()
	CODE:
		RETVAL = TNT_OP_CALL;
	OUTPUT:
		RETVAL

unsigned _op_ping()
	CODE:
		RETVAL = TNT_OP_PING;
	OUTPUT:
		RETVAL


unsigned _flag_return()
	CODE:
		RETVAL = TNT_FLAG_RETURN;
	OUTPUT:
		RETVAL

unsigned _flag_add()
	CODE:
		RETVAL = TNT_FLAG_ADD;
	OUTPUT:
		RETVAL

unsigned _flag_replace()
	CODE:
		RETVAL = TNT_FLAG_REPLACE;
	OUTPUT:
		RETVAL

unsigned _flag_box_quiet()
	CODE:
		RETVAL = TNT_FLAG_BOX_QUIET;
	OUTPUT:
		RETVAL

unsigned _flag_not_store()
	CODE:
		RETVAL = TNT_FLAG_NOT_STORE;
	OUTPUT:
		RETVAL

