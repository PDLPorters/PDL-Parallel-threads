PDL-Parallel-threads
====================

Sharing PDL data between Perl threads

See the documentation for PDL::Parallel::threads for more about the module.
This covers installation.

To begin, the easiest way to install this module is to use cpanm to install
the tarball:

  cpanm https://github.com/run4flat/PDL-Parallel-threads/tarball/master

If you wish to install by hand, this is a typical Module::Build-based
distribution. First download the distribution using git or by directly
downloading the zip archive at

  https://github.com/run4flat/PDL-Parallel-threads/zipball/master

or the tar.gz tarball at

  https://github.com/run4flat/PDL-Parallel-threads/tarball/master

Unpack and navigate a command-line shell to the root directory. Then issue the
following commands:

  # Windows          Unixen (including modern Macs)
  perl Build.PL      perl Build.PL
  Build              ./Build
  Build test         ./Bulld test
  Build install      ./Build install
                          -- or --
                     sudo ./Build install

Please file bug reports on the github issue tracker:

  https://github.com/run4flat/PDL-Parallel-threads/issues

