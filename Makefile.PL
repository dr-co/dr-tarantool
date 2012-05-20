use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'DR::Tarantool',
    VERSION_FROM      => 'lib/DR/Tarantool.pm', # finds $VERSION
    PREREQ_PM         => {
            'Carp'                      => 0,
            'File::Temp'                => 0,
            'File::Path'                => 0,
            'File::Spec::Functions'     => 0,
            'Cwd'                       => 0,
            'IO::Socket::INET'          => 0,
            'AnyEvent'                  => 0,
            'Devel::GlobalDestruction'   => 0,
    }, # e.g., Module::Name => 1.1
    ABSTRACT_FROM  => 'lib/DR/Tarantool.pm', # retrieve abstract from module
    AUTHOR         => 'Dmitry E. Oboukhov <unera@debian.org>',
    LIBS              => ['-ltarantool'], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
	# Un-comment this if you add C files to link with later:
    OBJECT            => '$(O_FILES)', # link all the C files too
    LICENSE           => 'artistic',
);

if (open my $file, '+<', 'Makefile') {
    my @lines = <$file>;
    seek $file, 0, 0;
    truncate $file, 0;
    for (@lines) {
        $_ = "TEST_VERBOSE=1\n" if /^TEST_VERBOSE\s*=\s*.*/;
        print $file $_;
    }
}
