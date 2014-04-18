#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use Test::More tests    => 3;
use Encode qw(decode encode);


BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool::MsgPack::Proto', 'call_lua', 'response';
}


{
    my $p = response call_lua(121, 'test');
    is_deeply $p => {
        CODE            => 6,
        FUNCTION_NAME   => 'test',
        SYNC            => 121,
        TUPLE           => []
    }, 'Call request';
}

{
    my $p = response call_lua(121, 'test', 1, [2, 3], 4);
    is_deeply $p => {
        CODE            => 6,
        FUNCTION_NAME   => 'test',
        SYNC            => 121,
        TUPLE           => [1, [2, 3], 4]
    }, 'Call request';
}
