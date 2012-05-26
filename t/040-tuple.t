#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 49;
use Encode qw(decode encode);


BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool::Spaces';
    use_ok 'DR::Tarantool::Tuple';
}

my $s = DR::Tarantool::Spaces->new({
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


my $tp = new DR::Tarantool::Tuple( [ 'aa', 'bb', 'cc' ], $s->space('test') );
isa_ok $tp => 'DR::Tarantool::Tuple';

cmp_ok $tp->raw(0), '~~', 'aa', 'raw(0)';
cmp_ok $tp->a, '~~', 'aa', 'raw(0)';
cmp_ok $tp->raw(1), '~~', 'bb', 'raw(1)';
cmp_ok $tp->b, '~~', 'bb', 'raw(1)';
cmp_ok $tp->raw(2), '~~', 'cc', 'raw(2)';
cmp_ok $tp->c, '~~', 'cc', 'raw(2)';
ok @{ $tp->raw } ~~ @{[qw(aa bb cc)]}, 'raw';
cmp_ok $tp->raw(3), '~~', undef, 'raw(3)';
cmp_ok $tp->d, '~~', undef, 'raw(3)';
ok !eval { $tp->unknown; 1 }, 'unknown';

my $tp2 = $tp->next(['dd', 'ee']);
my $tp3 = $tp->next(['ff', 'gg']);
isa_ok $tp2 => 'DR::Tarantool::Tuple';
isa_ok $tp3 => 'DR::Tarantool::Tuple';

cmp_ok $tp2->raw(0), '~~', 'dd', 'tp2->raw(0)';
cmp_ok $tp2->raw(1), '~~', 'ee', 'tp2->raw(1)';
cmp_ok $tp3->raw(0), '~~', 'ff', 'tp3->raw(0)';
cmp_ok $tp3->raw(1), '~~', 'gg', 'tp3->raw(1)';

my $it = $tp->iter;
isa_ok $it => 'DR::Tarantool::Tuple::Iterator';
cmp_ok $it->count, '~~', 3, 'count';

$tp = $it->next;
cmp_ok $tp->raw(0), '~~', 'aa', 'raw(0)';
cmp_ok $tp->raw(1), '~~', 'bb', 'raw(1)';
$tp = $it->next;
cmp_ok $tp->raw(0), '~~', 'dd', 'raw(0)';
cmp_ok $tp->raw(1), '~~', 'ee', 'raw(1)';
$tp = $it->next;
cmp_ok $tp->raw(0), '~~', 'ff', 'raw(0)';
cmp_ok $tp->raw(1), '~~', 'gg', 'raw(1)';
$tp = $it->next;
cmp_ok $tp, '~~', undef, 'iterator finished';


while( my $t = $it->next ) {
    isa_ok $t => 'DR::Tarantool::Tuple';
}
while( my $t = $it->next ) {
    isa_ok $t => 'DR::Tarantool::Tuple';
}

$tp = new DR::Tarantool::Tuple( [ [ 'aa' ], [ 'bb' ], [ 'cc' ] ],
    $s->space('test')
);

cmp_ok $tp->raw(0), '~~', 'aa', 'tuple[0]';
cmp_ok $tp->next->raw(0), '~~', 'bb', 'tuple[0]';
cmp_ok $tp->next->next->raw(0), '~~', 'cc', 'tuple[0]';

$tp = DR::Tarantool::Tuple->unpack(
    [ pack('L<', 10), pack('L<', 20) ], $s->space('test')
);
isa_ok $tp => 'DR::Tarantool::Tuple';
cmp_ok $tp->raw(0), '~~', 10, 'raw(0)';
cmp_ok $tp->raw(1), '~~', 20, 'raw(1)';

$tp = new DR::Tarantool::Tuple( [ [ 'aa' ], [ 'bb' ], ], $s->space('test') );
isa_ok $tp => 'DR::Tarantool::Tuple';
cmp_ok $tp->iter->count, '~~', 2, 'create tuple list';

my $iter = $tp->iter;
isa_ok $iter => 'DR::Tarantool::Tuple::Iterator', 'iterator';
isa_ok $iter->next => 'DR::Tarantool::Tuple', 'no iterator class';

$iter = $tp->iter('TestItem');
isa_ok $iter => 'DR::Tarantool::Tuple::Iterator', 'iterator with TestItem';
$tp = $iter->next;
isa_ok $tp => 'TestItem';
isa_ok $tp->{tuple} => 'DR::Tarantool::Tuple';
cmp_ok $tp->{tuple}->raw(0), '~~', 'aa',  'tuple(0).raw(0)';
cmp_ok $iter->next->{tuple}->raw(0), '~~', 'bb', 'tuple(1).raw(0)';


package TestItem;

sub new {
    my ($class, $tuple) = @_;
    return bless { tuple => $tuple } => $class;
}




