=head1 NAME

DR::Tarantool::Iterator - iterator/container class for L<DR::Tarantool>

=head1 SYNOPSIS

    use DR::Tarantool::Iterator;

    my $iter = DR::Tarantool::Iterator->new([1, 2, 3]);

    my $item0 = $iter->item(0);

    my @all = $iter->all;
    my $all = $iter->all;

    while(my $item = $iter->next) {
        do_something_with_item( $item );
    }


=head1 METHODS

=cut

use utf8;
use strict;
use warnings;

package DR::Tarantool::Iterator;
use Carp;
use Data::Dumper;


=head2 new

Constructor.

=head3 Arguments

=over

=item *

Array of items.

=item *

List of named arguments, that can be:

=over

=item item_class

Name of class to bless/construct item. If the field is 'B<ARRAYREF>'
then the first element of the array is B<item_class>, and the second
element is B<item_constructor>.

=item item_constructor

Name of constructor for item. If the value is undefined
and B<item_class> is defined, iterator will bless value instead construct.

If B<item_constructor> is used, constructor method will be receive three
arguments: B<item>, B<item_index> and B<iterator>.


    my $iter = DR::Tarantool::Iterator->new(
        [ [1], [2], [3] ],
        item_class => 'MyClass',
        item_constructor => 'new'
    );

    my $iter = DR::Tarantool::Iterator->new(    # the same
        [ [1], [2], [3] ],
        item_class => [ 'MyClass', 'new' ]
    );


    my $item = $iter->item(0);
    my $item = MyClass->new( [1], 0, $iter );  # the same

    my $item = $iter->item(2);
    my $item = MyClass->new( [3], 2, $iter );  # the same

=item data

Any Your data You want to assign to iterator.

=back

=back

=cut

sub new {
    my ($class, $items, %opts) = @_;

    croak 'usage: DR::Tarantool::Iterator->new([$item1, $item2, ... ], %opts)'
        unless 'ARRAY' eq ref $items;


    my $self = bless { items   => $items } => ref($class) || $class;

    $self->item_class(
        ('ARRAY' eq ref $opts{item_class}) ?
            @{ $opts{item_class} } : $opts{item_class}
    ) if exists $opts{item_class};

    $self->item_constructor($opts{item_constructor})
        if exists $opts{item_constructor};

    $self->data( $opts{data} ) if exists $opts{data};
    $self;
}


=head2 clone(%opt)

clone iterator object (doesn't clone items).
It is usable if You want to have iterator that have the other B<item_class>
and (or) B<item_constructor>.

If B<clone_items> argument is true, the function will clone itemlist, too.

    my $iter1 = $old_iter->clone(item_class => [ 'MyClass', 'new' ]);
    my $iter2 = $old_iter->clone(item_class => [ 'MyClass', 'new' ],
        clone_items => 1);

    $old_iter->sort(sub { $_[0]->name cmp $_[1]->name });
    # $iter1 will be resorted, too, but $iter2 will not be

=cut

sub clone {

    my $self = shift;
    my %opts;
    if (@_ == 1) {
        %opts = (clone_items => shift);
    } else {
        %opts = @_;
    }

    my %pre = (
        data                => $self->data,
        item_class          => $self->item_class,
        item_constructor    => $self->item_constructor
    );

    my $clone_items = delete $opts{clone_items};

    my $items = $clone_items ? [ @{ $self->{items} } ] : $self->{items};
    $self = $self->new( $items, %pre, %opts );
    $self;
}


=head2 count

returns count of items that are contained in iterator

=cut

sub count {
    my ($self) = @_;
    return scalar @{ $self->{items} };
}


=head2 item

returns one item from iterator by its number
(or croaks error for wrong numbers)

=cut

sub item {
    my ($self, $no) = @_;

    my $item = $self->raw_item( $no );

    if (my $class = $self->item_class) {

        if (my $m = $self->item_constructor) {
            return $class->$m( $item, $no, $self );
        }

        return bless $item => $class if ref $item;
        return bless \$item => $class;
    }

    return $self->{items}[ $no ];
}


=head2 raw_item

returns one raw item from iterator by its number
(or croaks error for wrong numbers).

The function differ from L<item>: it doesn't know about 'B<item_class>'.

=cut

sub raw_item {
    my ($self, $no) = @_;

    my $exists = $self->exists($no);
    croak "wrong item number format: " . (defined($no) ? $no : 'undef')
        unless defined $exists;
    croak 'wrong item number: ' . $no unless $exists;

    if ($no >= 0) {
        croak "iterator doesn't contain item with number $no"
            unless $no < $self->count;
    } else {
        croak "iterator doesn't contain item with number $no"
            unless $no >= -$self->count;
    }

    return $self->{items}[ $no ];
}


=head2 raw_sort(&)

resorts iterator (changes current object). Compare function receives two B<raw>
objects:

    $iter->raw_sort(sub { $_[0]->field cmp $_[1]->field });

=cut

sub raw_sort {
    my ($self, $cb) = @_;
    my $items = $self->{items};
    @$items = sort { &$cb($a, $b) } @$items;
    return $self;
}


=head2 sort(&)

resorts iterator (changes current object). Compare function receives
two objects:

    $iter->sort(sub { $_[0]->field <=> $_[1]->field });

=cut

sub sort : method {
    my ($self, $cb) = @_;
    my $items = $self->{items};
    my @bitems = map { $self->item( $_ )  } 0 .. $#$items;
    my @isorted = sort { &$cb( $bitems[$a], $bitems[$b] )  } 0 .. $#$items;

    @$items = @$items[ @isorted ];
    return $self;
}


=head2 grep(&)

greps iterator (returns new iterator).

    my $admins = $users->grep(sub { $_[0]->is_admin });

=cut

sub grep :method {
    my ($self, $cb) = @_;
    my $items = $self->{items};
    my @bitems = map { $self->item( $_ ) } 0 .. $#$items;
    my @igrepped = grep { &$cb( $bitems[$_] )  } 0 .. $#$items;
    @igrepped = @$items[ @igrepped ];

    return $self->new(
        \@igrepped,
        item_class => $self->item_class,
        item_constructor => $self->item_constructor,
        data => $self->data
    );
}


=head2 raw_grep(&)

greps iterator (returns new iterator). grep function receives raw item.

    my $admins = $users->grep(sub { $_[0]->is_admin });

=cut

sub raw_grep :method {
    my ($self, $cb) = @_;
    my $items = $self->{items};
    my @igrepped = grep { &$cb($_) } @$items;

    return $self->new(
        \@igrepped,
        item_class => $self->item_class,
        item_constructor => $self->item_constructor,
        data => $self->data
    );
}


=head2 get

The same as L<item> method.

=cut

sub get { goto \&item; }


=head2 exists

Returns B<true> if iterator contains element with noticed index.

    my $item = $iter->exists(10) ? $iter->get(10) : somethig_else();

=cut

sub exists : method{
    my ($self, $no) = @_;
    return undef unless defined $no;
    return undef unless $no =~ /^-?\d+$/;
    return 0 if $no >= $self->count;
    return 0 if $no <  -$self->count;
    return 1;
}


=head2 next

returns next element from iterator (or B<undef> if eof).

    while(my $item = $iter->next) {
        do_something_with( $item );
    }

You can ask current element's number by function 'L<iter>'.

=cut

sub next :method {
    my ($self) = @_;
    my $iter = $self->iter;

    if (defined $self->{iter}) {
        return $self->item(++$self->{iter})
            if $self->iter < $#{ $self->{items} };
        delete $self->{iter};
        return undef;
    }

    return $self->item($self->{iter} = 0) if $self->count;
    return undef;
}


=head2 iter

returns current iterator index.

=cut

sub iter {
    my ($self) = @_;
    return $self->{iter};
}


=head2 reset

resets iterator index, returns previous index value.

=cut

sub reset :method {
    my ($self) = @_;
    return delete $self->{iter};
}


=head2 all

returns all elements from iterator.

    my @list = $iter->all;
    my $list_aref = $iter->all;

    my @abc_list = map { $_->abc } $iter->all;
    my @abc_list = $iter->all('abc');               # the same


    my @list = map { [ $_->abc, $_->cde ] } $iter->all;
    my @list = $iter->all('abc', 'cde');                # the same


    my @list = map { $_->abc + $_->cde } $iter->all;
    my @list = $iter->all(sub { $_[0]->abc + $_->cde }); # the same


=cut

sub all {
    my ($self, @items) = @_;

    return unless defined wantarray;
    my @res;

    local $self->{iter};


    if (@items == 1) {
        my $m = shift @items;

        while (defined(my $i = $self->next)) {
            push @res => $i->$m;
        }
    } elsif (@items) {
        while (defined(my $i = $self->next)) {
            push @res => [ map { $i->$_ } @items ];
        }
    } else {
        while (defined(my $i = $self->next)) {
            push @res => $i;
        }
    }

    return @res if wantarray;
    return \@res;
}



=head2 item_class

set/returns item class. If the value isn't defined, iterator will
bless fields into the class (or calls L<item_constructor> in the class
if L<item_constructor> is defined

=cut

sub item_class {
    my ($self, $v, $m) = @_;
    $self->item_constructor($m) if @_ > 2;
    return $self->{item_class} = ref($v) || $v if @_ > 1;
    return $self->{item_class};
}


=head2 item_constructor

set/returns item constructor. The value can be used only if L<item_class>
is defined.

=cut

sub item_constructor {
    my ($self, $v) = @_;
    return $self->{item_constructor} = $v if @_ > 1;
    return $self->{item_constructor};
}


=head2 push

push item into iterator.

=cut

sub push :method {
    my ($self, @i) = @_;
    push @{ $self->{items}} => @i;
    return $self;
}


=head2 data

returns/set user's data assigned to the iterator

=cut

sub data {
    my ($self, $data) = @_;
    $self->{data} = $data if @_ > 1;
    return $self->{data};
}

1;
