# SWI-Prolog interface to R

This package provides library(r_session) that allows for communicating
with [The R Project for Statistical
Computing](http://www.r-project.org/). This package has been developed
by [Nicos Angelopoulos](mailto:nicos.angelopoulos@gmail.com) and has
been part of the SWI-Prolog default packages for several years as
library('R').

This library *has been superseeded* by the [real
pack](http://www.swi-prolog.org/pack/list?p=real), which provides a much
faster and robust interface to R by embedding the R dynamic library in
Prolog using the foreign library interface.  Still, the process based
approach can come handy:

  - It may be easier to install (depending on the platform)
  - It can run R on a remote computer that provides more resources
  - Multiple R engines may be created and destroyed.
  - On some platforms, R cannot open graphical windows when embedded
    in Prolog.

Documentation about this pack is in `doc/r_session.html` and a simple
demo is in `examples/r_demo.pl`.
