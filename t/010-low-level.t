#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use Test::More tests    => 80;
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

# call
$sbody = DR::Tarantool::_pkt_call_lua( 124, 125, 'tproc', [ 126, 127 ]);
ok defined $sbody, '* call body';
@a = unpack 'L< L< L< L< w/Z* L< L<', $sbody;
cmp_ok $a[0], '~~', 22, 'call type';
cmp_ok $a[1], '~~', length($sbody) - 3 * 4, 'body length';
cmp_ok $a[2], '~~', 124, 'request id';
cmp_ok $a[3], '~~', 125, 'flags';
cmp_ok $a[4], '~~', 'tproc',  'proc name';
cmp_ok $a[5], '~~', 2, 'tuple size';

# update
my @ops = map { [ int rand 100, $_, int rand 100 ] }
    qw(add and or xor set delete insert);
$sbody = DR::Tarantool::_pkt_update( 15, 16, 17, [ 18 ], \@ops);
ok defined $sbody, '* update body';
@a = unpack '( L< )*', $sbody;
cmp_ok $a[0], '~~', 19, 'update type';
cmp_ok $a[1], '~~', length($sbody) - 3 * 4, 'body length';
cmp_ok $a[2], '~~', 15, 'request id';
cmp_ok $a[3], '~~', 16, 'space no';
cmp_ok $a[4], '~~', 17, 'flags';
cmp_ok $a[5], '~~', 1,  'tuple size';


$sbody = DR::Tarantool::_pkt_call_lua( 124, 125, 'tproc', [  ]);

# parser
ok !eval { DR::Tarantool::_pkt_parse_response( undef ) }, '* parser: undef';
my $res = DR::Tarantool::_pkt_parse_response( '' );
isa_ok $res => 'HASH', 'empty input';
like $res->{errstr}, qr{too short}, 'error message';
cmp_ok $res->{status}, '~~', 'buffer', 'status';

for (13, 17, 19, 20, 22, 65280) {
    my $msg = "test message";
    my $data = pack 'L< L< L< L< Z*',
        $_, 5 + length $msg, $_ + 100, 0x0101, $msg;
    $res = DR::Tarantool::_pkt_parse_response( $data );
    isa_ok $res => 'HASH', 'well input ' . $_;
    cmp_ok $res->{req_id}, '~~', $_ + 100, 'request id';
    cmp_ok $res->{type}, '~~', $_, 'request type';
    cmp_ok $res->{status}, '~~', 'error', "status $_"
        unless $res->{type} == 65280;
    ok $res->{code} ~~ 0x101, 'code' unless $res->{type} == 65280;;
    cmp_ok $res->{errstr}, '~~', $msg, 'errstr' unless $res->{type} == 65280;
}


__END__
sub pack_tuple {
    my @f = map "$_", @_;
    $_ = pack 'w / a*', $_ for @f;
    my $tuple = pack 'L< a*', scalar(@f), @f;
    my $fq_tuple = pack 'L< / a*', $tuple;
    return $fq_tuple;
}


sub pack_tuples {
    return pack 'L< a*', scalar(@_), join '' => map { pack_tuple @$_ } @_;
}

my $sel_response = pack_tuples [ 'abc', 'def' ], [ 'ghi', 'jkl' ];
$sel_response = pack 'L< L< L< L< a*' =>
    17,
    length($sel_response) + 4,
    11,
    0,
    $sel_response;

$res = DR::Tarantool::_pkt_parse_response( $sel_response );

note explain $res, [ $sel_response ];


