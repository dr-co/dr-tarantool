#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 30;
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
                type    => 'NUM64',
                name    => 'a123',
            },
            {
                type    => 'STR',
                name    => 'abcd',
            }
        ],
        indexes => {
            0 => [ qw(a b) ],
            1 => 'd'
        }
    }
});

# note explain $s;

my $v = unpack 'L<', $s->pack_field( test => a => '10' );
cmp_ok $v, '~~', 10, 'pack_field NUM';
$v = unpack 'L<', $s->pack_field( test => 0 => 11 );
cmp_ok $v, '~~', 11, 'pack_field NUM';
$v = unpack 'L<', $s->pack_field( 0 => 0 => 13 );
cmp_ok $v, '~~', 13, 'pack_field NUM';
$v = unpack 'Q<', $s->pack_field( test => a123 => 13 );
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
cmp_ok unpack('Q<', $t->[4]), '~~', 10, 'tuple[4]';
cmp_ok $t->[5], '~~', 'test', 'tuple[5]';
