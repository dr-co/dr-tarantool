#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 84;
use Encode qw(decode encode);


BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool::Spaces';
}

use constant MODEL => 'DR::Tarantool::Spaces';


ok !eval { MODEL->new }, 'no arguments';
like $@, qr{HASHREF}, 'error message';
ok !eval { MODEL->new('abc') }, 'wrong arguments';
like $@, qr{HASHREF}, 'error message';
ok !eval { MODEL->new({a => 1}) }, 'wrong arguments';
like $@, qr{space number}, 'error message';
ok !eval { MODEL->new({}) }, 'empty spaces';

my $s = MODEL->new({
    0 => {
        name    => 'test',
        default_type    => 'NUM',
        fields  => [
            qw(a b c),
            {
                type    => 'UTF8STR',
                name    => 'd'
            },
            {
                type    => 'NUM',
                name    => 'a123',
            },
            {
                type    => 'STR',
                name    => 'abcd',
            }
        ],
        indexes => {
            0   => [ qw(a b) ],
            1   => 'd',
            2   => 'c',
            3   => {
                name    => 'abc',
                fields  => [ qw(a b c) ]
            }
        }
    }
});

my $v = unpack 'L<', $s->pack_field( test => a => '10' );
cmp_ok $v, '~~', 10, 'pack_field NUM';
$v = unpack 'L<', $s->pack_field( test => 0 => 11 );
cmp_ok $v, '~~', 11, 'pack_field NUM';
$v = unpack 'L<', $s->pack_field( 0 => 0 => 13 );
cmp_ok $v, '~~', 13, 'pack_field NUM';
$v = unpack 'L<', $s->pack_field( test => a123 => 13 );
cmp_ok $v, '~~', 13, 'pack_field NUM64';
$v = $s->pack_field( test => d => 'test' );
cmp_ok $v, '~~', 'test', 'pack_field STR';
$v = decode utf8 => $s->pack_field( test => d => 'привет' );
cmp_ok $v, '~~', 'привет', 'pack_field STR';

$v = decode utf8 => $s->pack_field( test => d => encode utf8 => 'привет' );
cmp_ok $v, '~~', 'привет', 'pack_field STR';


$v = $s->unpack_field( test => a => pack 'L<' => 14);
cmp_ok $v, '~~', 14, 'unpack_field NUM';
$v = $s->unpack_field( test => 0 => pack 'L<' => 14);
cmp_ok $v, '~~', 14, 'unpack_field NUM';
$v = $s->unpack_field( 0 => 0 => pack 'L<' => 14);
cmp_ok $v, '~~', 14, 'unpack_field NUM';
$v = $s->unpack_field( 0 => 'abcd' => 'test');
cmp_ok $v, '~~', 'test', 'unpack_field STR';
$v = $s->unpack_field( 0 => 'abcd' => 'привет');
cmp_ok $v, '~~', encode(utf8 => 'привет'), 'unpack_field STR';
$v = $s->unpack_field( 0 => 'd' => 'привет');
cmp_ok $v, '~~', 'привет', 'unpack_field STR';

my $tt = [0, 1, 2, 'медвед', 10, 'test'];
my $t = $s->pack_tuple(test => $tt);
isa_ok $t => 'ARRAY';
my $ut = $s->unpack_tuple(0 => $t);
isa_ok $ut => 'ARRAY';
ok @$tt ~~ @$ut, 'unpacked packed tuple';

cmp_ok unpack('L<', $t->[0]), '~~', 0, 'tuple[0]';
cmp_ok unpack('L<', $t->[1]), '~~', 1, 'tuple[1]';
cmp_ok unpack('L<', $t->[2]), '~~', 2, 'tuple[2]';
cmp_ok $t->[3], '~~', encode(utf8 => 'медвед'), 'tuple[3]';
cmp_ok unpack('L<', $t->[4]), '~~', 10, 'tuple[4]';
cmp_ok $t->[5], '~~', 'test', 'tuple[5]';

# indexes
$t = $s->space('test')->pack_keys([1, 2], 'i0');
ok @{ $t->[0] } ~~ @{[ pack('L<', 1), pack 'L<', 2 ]}, 'pack_keys';
$t = $s->space('test')->pack_keys([[2, 3]], 'i0');
ok @{ $t->[0] } ~~ @{[ pack('L<', 2), pack 'L<', 3 ]}, 'pack_keys';
$t = eval { $s->space('test')->pack_keys(1, 'i0'); };
like $@, qr{must have 2}, 'error message';
cmp_ok $t, '~~', undef, 'wrong elements count';

$t = $s->space('test')->pack_keys([1, 2], 0);
ok @{ $t->[0] } ~~ @{[ pack('L<', 1), pack 'L<', 2 ]}, 'pack_keys';
$t = $s->space('test')->pack_keys([[2, 3]], 0);
ok @{ $t->[0] } ~~ @{[ pack('L<', 2), pack 'L<', 3 ]}, 'pack_keys';
$t = eval { $s->space('test')->pack_keys(1, 0); };
like $@, qr{must have 2}, 'error message';
cmp_ok $t, '~~', undef, 'wrong elements count';

$t = $s->space('test')->pack_keys(4, 'i2');
cmp_ok unpack('L<', $t->[0][0]), '~~', 4, 'pack_keys';
$t = $s->space('test')->pack_keys([5], 'i2');
cmp_ok unpack('L<', $t->[0][0]), '~~', 5, 'pack_keys';
$t = $s->space('test')->pack_keys([[6]], 'i2');
cmp_ok unpack('L<', $t->[0][0]), '~~', 6, 'pack_keys';
$t = $s->space('test')->pack_keys([7,8,9], 'i2');
cmp_ok unpack('L<', $t->[0][0]), '~~', 7, 'pack_keys';
cmp_ok unpack('L<', $t->[1][0]), '~~', 8, 'pack_keys';
cmp_ok unpack('L<', $t->[2][0]), '~~', 9, 'pack_keys';
$t = eval { $s->space('test')->pack_keys([[7,8,9]], 'i2') };
like $@, qr{must have 1}, 'error message';

# pack_operation
my $op = $s->space('test')->pack_operation([d => 'delete']);
cmp_ok $op->[0], '~~', 3, '* operation field';
cmp_ok $op->[1], '~~', 'delete', 'operation name';

for (qw(insert add and or xor set)) {
    my $n = int rand 100000;
    $op = $s->space('test')->pack_operation([a123 => $_ => $n]);
    cmp_ok $op->[0], '~~', 4, "operation field: $_";
    cmp_ok $op->[1], '~~', $_, 'operation name';
    cmp_ok unpack('L<', $op->[2]), '~~', $n, 'operation argument';
}

$op = $s->space('test')->pack_operation([d => 'substr', 1, 2]);
cmp_ok $op->[0], '~~', 3, 'operation field: substr';
cmp_ok $op->[1], '~~', 'substr', 'operation name';
cmp_ok $op->[2], '~~', 1, 'operation argument 1';
cmp_ok $op->[3], '~~', 2, 'operation argument 2';
cmp_ok $op->[4], '~~', undef, 'operation argument 3';

$op = $s->space('test')->pack_operation([d => 'substr', 231, 232, 'привет']);
cmp_ok $op->[0], '~~', 3, 'operation field: substr';
cmp_ok $op->[1], '~~', 'substr', 'operation name';
cmp_ok $op->[2], '~~', 231, 'operation argument 1';
cmp_ok $op->[3], '~~', 232, 'operation argument 2';
cmp_ok $op->[4], '~~', 'привет', 'operation argument 3';

$op = $s->space('test')->pack_operations([ d => set => 'тест']);
cmp_ok $op->[0][0], '~~', 3, "operation field: set";
cmp_ok $op->[0][1], '~~', 'set', 'operation name';
cmp_ok decode(utf8 => $op->[0][2]), '~~', 'тест', 'operation argument';
$op = $s->space('test')->pack_operations([
    [ d => set => 'тест'], [1 => insert => 500]
]);
cmp_ok $op->[0][0], '~~', 3, "operation field: set";
cmp_ok $op->[0][1], '~~', 'set', 'operation name';
cmp_ok decode(utf8 => $op->[0][2]), '~~', 'тест', 'operation argument';

cmp_ok $op->[1][0], '~~', 1, "operation field: set";
cmp_ok $op->[1][1], '~~', 'insert', 'operation name';
cmp_ok unpack('L<', $op->[1][2]), '~~', 500, 'operation argument';
