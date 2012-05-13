#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use Test::More tests    => 1;
use Encode qw(decode encode);


BEGIN {
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool'
}


# SELECT
my $sbody = DR::Tarantool::_pkt_select( 9, 8, 7, 6, 5, [ [4], [3] ] );
ok defined $sbody, '* select body';

my @a = unpack '( L< )*', $sbody;
cmp_ok $a[0], '~~', 17, 'select type';
cmp_ok $a[1], '~~', length($sbody) - 3 * 4, 'body length';
cmp_ok $a[2], '~~', 9, 'request id';
cmp_ok $a[3], '~~', 8, 'space no';
cmp_ok $a[4], '~~', 7, 'index no';
cmp_ok $a[5], '~~', 6, 'offset';
cmp_ok $a[6], '~~', 5, 'limit';
cmp_ok $a[7], '~~', 2, 'tuple count';
ok !eval { DR::Tarantool::_pkt_select( 1, 2, 3, 4, 5, [ 6 ] ) }, 'keys format';
like $@ => qr{ARRAYREF of ARRAYREF}, 'error string';

# PING
$sbody = DR::Tarantool::_pkt_ping( 11 );
ok defined $sbody, '* ping body';
@a = unpack '( L< )*', $sbody;
cmp_ok $a[0], '~~', 65280, 'ping type';
cmp_ok $a[1], '~~', length($sbody) - 3 * 4, 'body length';
cmp_ok $a[2], '~~', 11, 'request id';


# insert
$sbody = DR::Tarantool::_pkt_insert( 12, 13, 14, [ 'a', 'b', 'c', 'd' ]);
ok defined $sbody, '* insert body';
@a = unpack '( L< )*', $sbody;
cmp_ok $a[0], '~~', 13, 'insert type';
cmp_ok $a[1], '~~', length($sbody) - 3 * 4, 'body length';
cmp_ok $a[2], '~~', 12, 'request id';
cmp_ok $a[3], '~~', 13, 'space no';
cmp_ok $a[4], '~~', 14, 'flags';
cmp_ok $a[5], '~~', 4,  'tuple size';

# update
$sbody = DR::Tarantool::_pkt_update( 15, 16, 17, [ 18 ], [ [ 1 => add => 1 ] ]);
ok defined $sbody, '* update body';
@a = unpack '( L< )*', $sbody;
cmp_ok $a[0], '~~', 19, 'update type';
cmp_ok $a[1], '~~', length($sbody) - 3 * 4, 'body length';
cmp_ok $a[2], '~~', 15, 'request id';
cmp_ok $a[3], '~~', 16, 'space no';
cmp_ok $a[4], '~~', 17, 'flags';
cmp_ok $a[5], '~~', 1,  'tuple size';

# delete
$sbody = DR::Tarantool::_pkt_delete( 119, 120, 121, [ 122, 123 ] );
ok defined $sbody, '* delete body';
@a = unpack '( L< )*', $sbody;
cmp_ok $a[0], '~~', 20, 'delete type';
cmp_ok $a[1], '~~', length($sbody) - 3 * 4, 'body length';
cmp_ok $a[2], '~~', 119, 'request id';

cmp_ok $a[3], '~~', 120, 'space no';
# cmp_ok $a[4], '~~', 121, 'flags';  # libtarantool ignores flags
cmp_ok $a[4], '~~', 2,  'tuple size';

# SV * _pkt_update(req_id, ns, flags, tuple, operations)
