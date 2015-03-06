/*  Part of SWI-Prolog

    Author:        Nicos Angelopoulos
    WWW:           http://www.swi-prolog.org
    Copyright (C): Nicos Angelopoulos

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.

    Alternatively, this program may be distributed under the Perl
    Artistic License, version 2.0.
*/

:- module( r_session,
          [
               r_open/0, r_open/1, r_start/0,
               r_close/0, r_close/1,
               r_in/1, r_in/2,
               r_push/1, r_push/2,
               r_out/2, r_out/3,
               r_err/3, r_err/4,
               r_print/1, r_print/2,
               r_lines_print/1, r_lines_print/2, r_lines_print/3,
               r_lib/1, r_lib/2,
               r_flush/0, r_flush/1,
               r_flush_onto/2, r_flush_onto/3,
               current_r_session/1, current_r_session/3,
               default_r_session/1,
               r_session_data/3, r_streams_data/3,
               r_history/0, r_history/1, r_history/2,
               r_session_version/1,
               r_bin/1,
               r_bin_version/1, r_bin_version/2,
               r_verbosity/1,
               '<-'/2,
               op( 950, xfx, (<-) )
          ] ).

:- use_module( library(lists) ).
:- use_module( library(readutil) ). % read_line_to_codes/2.
:- set_prolog_flag(double_quotes, codes).

:- ( current_predicate(r_verbosity_level/1) -> true;
          assert(r_verbosity_level(0)) ).

:- dynamic( r_bin_location/1 ).
:- dynamic( r_session/3 ).
:- dynamic( r_session_history/2 ).
:- dynamic( r_old_bin_warning_issued/1 ).
:- dynamic( r_bin_takes_interactive/2 ).

:- multifile settings/2.

settings( '$r_internal_ignore', true ).   % just so we know settings is defined
% Swi declaration:
:- ensure_loaded( library(process) ).   % process_create/3.
:- at_halt( r_close(all) ).
% end of Swi declaration.

/** <module> R session

This library facilitates interaction with the R system for statistical
computing.  It assumes an R executable in $PATH or can be given a location
to a functioning R executable (see r_bin/1 and r_open/1 for details on how
R is located). R is ran as a slave with Prolog writing on and reading from
the associated streams. Multiple sessions can be managed simultaneously.
Each has 3 main components: a name or alias, a term structure holding the
communicating streams and a number of associated data items.

The library attempts to ease the translation between prolog terms and R
inputs. Thus, Prolog term =|x <- c(1,2,3)|= is translated to atomic =|'x
<- c(1,2,3)'|= which is then passed on to R. That is, =|<-|= is a
defined/recognised operator. =|X <- c(1,2,3)|=, where X is a variable,
instantiates X to the list =|[1,2,3]|=. Also 'Atom' <- [x1,...,xn]
translates to R code: Atom <- c(x1,...,xn). Currently vectors, matrices
and (R)-lists are translated in this fashion.  The goal "A <- B" translates to
r_in( A <- B ).

Although the library is primarily meant to be used as a research tool,
it still provides access to many functions of the R system that may render it
useful to a wider audience. The library provides access to R's plethora of vector and scalar
functions. We adicipate that of particular interest to Prolog programmers might be the fact
that the library can be used to create plots from Prolog objects.
Notably creating plots from lists of numbers.

There is a known issue with X11 when R is started without --interactive. R.pl runs by default
the --interactive flag and try to surpress echo output. If you do get weird output, try
giving to r_open, option with(non_interactive). This is suboptimal for some tasks, but
might resolve other issues. There is a issue with Macs, where --interactive doesnot work.
On Macs, you should use with(non_interactive). This can also be achieved using settings/2.

These capabilities are illustrated in the following example :

==
rtest :-
     r_open,
     y <- rnorm(50),
     r_print( y ),
     x <- rnorm(y),
     r_in( x11(width=5,height=3.5) ),
     r_in( plot(x,y) ),
     write( 'Press Return to continue...' ), nl,
     read_line_to_codes( user_input, _ ),
     r_print( 'dev.off()' ),
     Y <- y,
     write( y(Y) ), nl,
     findall( Zx, between(1,9,Zx), Z ),
     z <- Z,
     r_print( z ),
     cars <- c(1, 3, 6, 4, 9),
     r_in(pie(cars)),
     write( 'Press Return to continue...' ), nl,
     read_line_to_codes( user_input, _ ),
     r_close.
==

@author		Nicos Angelopoulos
@version	0:0:7
@copyright	Nicos Angelopoulos
@license	GPL+SWI-exception or Artistic 2.0
@see		ensure_loaded(library('../doc/packages/examples/R/r_demo.pl'))
@see		http://www.r-project.org/
*/

%%% Section: Interface predicates

%% r_bin( ?Rbin )
%
%   Register the default R location, +Rbin, or interrogate the current location: -Rbin.
%   When interrogating Rbin is bound to the R binary that would be used by an r_open/0.
%   The order of search is: registered location, environment variable 'R_BIN' and path defined.
%   On unix systems path defined is the first R executable in $PATH. On MS wins it is the latest
%   Rterm.exe found by expand_file_name( 'C:/Program Files/R/R-*/bin/Rterm.exe', Candidates ).
%   The value Rbin == =retract= retracts the current registered location.
%   Rbin == =test=, succeeds if an R location has been registered.
%
r_bin( Rbin ) :-
     var( Rbin ),
     !,
     ( r_bin_location(Rbin) ->
          true
          ;
          ( locate_rbin_file(Rbin) ->
               M = 'There is no registered R executable. Using the one found by searching.',
               r_verbose( M, 1 )
               ;
               M = 'There is no registered or default R executatble. Use, r_bin(+Rbin).',
               fail_term( M )
          )
     ).
r_bin( retract ) :-
     !,
     retractall( r_bin_location(_) ).
r_bin( test ) :-
     !,
     r_bin_location(_).
r_bin( Rbin ) :-
     retractall( r_bin_location(_) ),
     assert( r_bin_location(Rbin) ).

%%	r_open
%
%	Open a new R session. Same as r_open( [] ).
%
r_open :-
     r_open( [] ).

%%   r_start
%
%    Only start and session via r_open/1, if no open session existss.
%
r_start :-
     default_r_session( _R ),
     !.
r_start :-
     r_open.

%% r_open( +Opts )
%
%   Open a new R session with optional list of arguments. Opts should be
%   a list of the following
%
%       * alias(Alias)
%	Name for the session. If absent or  a variable an opaque term is
%	generated.
%
%       * assert(A)
%	Assert token. By default session  opened   last  is  the default
%	session (see default_r_session/1). Using A =   =z= will push the
%	session to the bottom of the pile.
%
%       * at_r_halt(RHAction)
%	R slaves used to halt when they encounter an error. This is no
%	longer the case but this option is still present in case it is
%	useful in the future. This option provides a handle to changing
%	the behaviour of the session when a halt of the R-slave occurs.
%	RHAction should be one of =abort=, =fail=, call/1,
%	call_ground/1, =reinstate= or =restart=. Default is =fail=. When
%	RHAction is =reinstate=, the history of the session is used to
%	roll-back all the commands sent so far. At `restart' the session
%	is restarted with same name and options, but history is not
%	replayed.
%
%       * copy(CopyTo,CopyWhat)
%	Records interaction with R to a   file/stream.  CopyTo should be
%	one   of   =null=,   stream(Stream),   OpenStream,   AtomicFile,
%	once(File) or many(File). In the  case   of  many(File), file is
%	opened and closed at each write   operation.  CopyWhat should be
%	one of =both=, =in=, =out= or =none=. Default is no recording
%       (CopyTo = =null=).
%
%       * ssh(Host)
%       * ssh(Host,Dir)
%       Run R on Host with start directory Dir. Dir defaults to /tmp.
%       Not supported on MS Windows.
%
%
%       * rbin(Rbin)
%	R executable location to use for this open operation. If the
%	option is not present binary registered with r_bin/1 and
%	environment variable R_BIN are examined for the full location of
%	the R binary. In MS windows Rbin should point to Rterm.exe. Also
%	see r_bin/1.
%
%       * with(With)
%	With is in [environ,non_interactive,restore,save]. The default
%	behaviour is to start the R executable with flags =|interactive
%	--no-environ --no-restore --no-save|=. For each With value found
%	in Opts the corresponding =|--no-|= flag is removed. In the case
%	of non_interactive, it removes the default --interactive. This
%	makes the connection more robust, and allows proper x11 plots in
%	linux. However you get alot all the echos of what you pipe in,
%	back from R.
%
r_open( Opts ) :-
     findall( S, r_session:settings(r_open_opt,S), Set ),
     append( Opts, Set, All ),
     r_open_1( All, _R, false ).

%%   r_close
%
%         Close the default R session.
%
r_close :-
     ( default_r_session( Alias ) ->
               r_close( Alias )
               ;
               fail_term( no_default_open_r_session_could_be_found_to_close )
     ).

%%   r_close(+R)
%
%         Close the named R session.
%
r_close( All ) :-
     All == all,
     !,
     findall( Alias, ( retract( r_session(Alias,Streams,Data) ),
                       r_close_session( Alias, Streams, Data ) ), _AllAls ).
     % write( closed_all(All) ), nl.
r_close( Alias ) :-
     ( retract( r_session(Alias,Streams,Data) ) ->
          r_close_session( Alias, Streams, Data )
          ;
          fail_term( no_open_r_session_could_be_found_to_close_at:Alias )
     ).

%%   r_in(+Rcmd)
%
%         Push Rcmd to the default R session. Output and Errors  will be
%         printed to the terminal.
%
r_in( This ) :-
     default_r_session( R ),
     r_in( R, This, _ ).

%%   r_in(+R,+Rcmd)
%
%         As r_in/1 but for session R.
%
r_in( R, PrvThis ) :-
     r_in( R, PrvThis, _ ).

%%   r_push(+Rcmd)
%
%         As r_in/1 but does not consume error or output streams.
%
r_push( This ) :-
     default_r_session( R ),
     r_push( R, This ).

%%   r_push(+R,+Rcmd)
%
%         As r_push/1 but for named session.
%
r_push( R, RCmd ) :-
     current_r_session( R, Streams, Data ),
     r_session_data( copy_to, Data, CopyTo ),
     r_session_data( copy_this, Data, CopyThis ),
     r_streams( input, Streams, Ri ),
     r_input_normative( RCmd, RNrm ),
     write( Ri, RNrm ), nl( Ri ),
     flush_output( Ri ),
     r_record_term( CopyThis, CopyTo, RNrm ).

%%   r_out(+Rcmd,-Lines)
%
%         Push Rcmd to default R session and grab output lines Lines as
%         a list of code lists.
%
r_out( This, Read ) :-
     default_r_session( R ),
     r_out( R, This, Read ).

%%   r_out(+R,+Rcmd,-Lines)
%
%         As r_out/2 but for named session R.
%
r_out( R, RCmd, RoLns ) :-
     r_push( R, RCmd, Rplc, RoLns, ReLns, Halt, HCall ),
     r_lines_print( ReLns, error, user_error ),
     r_record_history( Halt, R, RCmd ),
     r_out_halted_record( Halt, R, RoLns ),
     replace_variables( Rplc ),
     call( HCall ).

%%   r_err(+Rcmd,-Lines,-ErrLines)
%
%         Push Rcmd to default R session and grab output lines Lines as
%         a list of code lists. Error lines are in ErrLines.
%
r_err( This, Read, ErrRead ) :-
     default_r_session( R ),
     r_err( R, This, Read, ErrRead ).

%%   r_err(+R,+Rcmd,-Lines, -ErrLines)
%
%         As r_err/3 but for named session R.
%
r_err( R, RCmd, RoLns, ReLns ) :-
     r_push( R, RCmd, Rplc, RoLns, ReLns, Halt, HCall ),
     r_lines_print( ReLns, error, user_error ),
     r_record_history( Halt, R, RCmd ),
     r_out_halted_record( Halt, R, RoLns ),
     replace_variables( Rplc ),
     call( HCall ).

%%   r_print(+X)
%
%         A shortcut for r_in( print(X) ).
%
r_print( This ) :-
     default_r_session( R ),
     r_print( R, This ).

%%   r_print(+R,+X)
%
%         As r_print/1 but for named session R.
%
r_print( R, This ) :-
     r_out( R, This, Read ),
     r_lines_print( Read, output ).

%%   r_lines_print( +Lines )
%
%         Print a list of code lists (Lines) to the user_output.
%         Lines would normally be read of an R stream.
%
r_lines_print( Lines ) :-
     r_lines_print( Lines, output, user_output ).

%%   r_lines_print( +Lines, +Type )
%
%         As r_lines_print/1 but Type declares whether to treat lines
%         as output or error response. In the latter case they are written
%         on user_error and prefixed with '!'.
%
r_lines_print( Lines, Type ) :-
     r_lines_print_type_stream( Type, Stream ),
     r_lines_print( Lines, Type, Stream ).

%%   r_lines_print( +Lines, +Type, +Stream )
%
%         As r_lines_print/3 but Lines are written on Stream.
%
r_lines_print( [], _Type, _Stream ).
r_lines_print( [H|T], Type, Stream ) :-
     atom_codes( Atm, H ),
     r_lines_print_prefix( Type, Stream ),
     write( Stream, Atm ), nl( Stream ),
     r_lines_print( T, Type, Stream ).

%%   r_lib(+L)
%
%         A shortcut for r_in( library(X) ).
%
r_lib( Lib ) :-
     default_r_session( R ),
     r_lib( R, Lib ).

%%   r_lib(+R,+L)
%
%            As r_lib/1 but for named session R.
%
r_lib( R, Lib ) :-
     r_in( R, library(Lib) ).

%%   r_flush
%
%         Flush default R's output and error on to the terminal.
%
r_flush :-
     default_r_session( R ),
     r_flush( R ).

%%   r_flush(+R)
%
%         As r_flush/0 but for session R.
%
r_flush( R ) :-
     r_flush_onto( R, [output,error], [Li,Le] ),
     r_lines_print( Li, output ),
     r_lines_print( Le, error ).

%%   r_flush_onto(+SAliases,-Onto)
%
%         Flush stream aliases to code lists Onto. SAliases
%         should be one of, or a list of, [output,error].
%
r_flush_onto( RinStreamS, OntoS ) :-
     default_r_session( R ),
     r_flush_onto( R, RinStreamS, OntoS ).

%% r_flush_onto(+R,+SAliases,-Onto)
%
%         As r_flush_onto/2 for specified session R.
%
r_flush_onto( R, RinStreams, Ontos ) :-
     ( is_list(RinStreams) -> RStreams = RinStreams; RStreams=[RinStreams] ),
     % to_list( RinStreamS, RinStreams ),
     r_input_streams_list( RStreams ),
     r_flush_onto_1( RStreams, R, ROntos ),
     ( is_list(RinStreams) -> Ontos = ROntos; Ontos=[ROntos] ).

%%   current_r_session(?R)
%         True if R is the name of current R session.
%         Can be used to enumerate all open sessions.
%
current_r_session( R ) :-
     var( R ),
     !,
     r_session( R, _Session, _Data ).
current_r_session( R ) :-
     r_session( R, _Session, _Data ),
     !.
current_r_session( R ) :-
     fail_term( 'Could not find session':R ).

%%   current_r_session(?R,?S,?D)
%
%         True if R is an open session with streams S
%         and data D (see introduction to the library).
%
current_r_session( Alias, R, Data ) :-
     r_session( Alias, R, Data ).

%% default_r_session(?R)
%
%         True if R is the default session.
%
default_r_session( R ) :-
     ( var(R) ->
          ( r_session(R,_Cp1,_Wh1) ->
               true
               ;
               fail_term( no_default_open_r_session_was_found )
          )
          ;
          ( r_session(R,_Cp2,_Wh2) ->
               true
               ;
               fail_term( no_open_r_session_at(R) )
          )
     ).

%%   r_streams_data(+SId,+Streams,-S)
%         True if Streams is an R session streams
%         structure and S is its stream corresponding
%         to identifier SId, which should be one of
%         [input,output,error].
%
r_streams_data( input,  r(Ri,_,_), Ri ).
r_streams_data( output, r(_,Ro,_), Ro ).
r_streams_data( error,  r(_,_,Re), Re ).

%% r_session_data(+DId,+Data,-Datum)
%
%         True if Data is a structure representing
%         R session associated data and Datum is its
%         data item corresponding to data identifier
%         DId. DId should be in
%         [at_r_halt,copy_to,copy_this,interactive,version,opts].
%
r_session_data( copy_to, rsdata(Copy,_,_,_,_,_), Copy ).
r_session_data( copy_this, rsdata(_,This,_,_,_,_), This ).
r_session_data( at_r_halt, rsdata(_,_,RHalt,_,_,_), RHalt ).
r_session_data( interactive, rsdata(_,_,_,Ictv,_,_), Ictv).
r_session_data( version, rsdata(_,_,_,Vers,_,_), Vers ).
r_session_data( opts, rsdata(_,_,_,_,_,Opts), Opts ).

%%   r_history
%
%         Print on user_output the history of the default session.
%
r_history :-
     default_r_session( R ),
     r_session_history( R, History ),
     reverse( History, Hicory ),
     write( history(R) ), nl, write('---' ), nl,
     ( (member(H,Hicory),write(H),nl,fail) -> true; true ),
     write( '---' ), nl.

%%   r_history(-H)
%
%         H unifies to the history list of the Rcmds fed into the default
%         session. Most recent command appears at the head of the list.
%
r_history( History ) :-
     default_r_session( R ),
     r_session_history( R, History ).

%%   r_history(?R,-H)
%         As r_history/1 but for named session R.
%         It can be used to enumerate all histories.
%         It fails when no session is open.
%
r_history( R, History ) :-
     r_session_history( R, History ).

%%   r_session_version(-Version)
%         Installed version. Version is of the form Major:Minor:Fix,
%         where all three are integers.
%
r_session_version( 0:0:7 ).

%% r_verbose( What, CutOff )
%
r_verbose( What, CutOff ) :-
     r_verbosity_level( Level ),
     ( CutOff > Level ->
          true
          ;
          write( What ), nl
     ).

%% r_verbosity( ?Level )
%
%    Set, +Level, or interrogate, -Level, the verbosity level. +Level could be
%    =false= (=0), =true= (=3) or an integer in {0,1,2,3}. 3 being the most verbose.
%    The default is 0. -Level will instantiate to the current verbosity level,
%    an integer in {0,1,2,3}.
%
r_verbosity( Level ) :-
     var( Level ),
     !,
     r_verbosity_level( Level ).
r_verbosity( Level ) :-
     ( Level == true ->
          Numeric is 3
          ;
          ( Level == false ->
               Numeric is 0
               ;
               ( integer(Level) ->
                    ( Level < 0 ->
                         write( 'Adjusting verbosity level to = 0. ' ), nl,
                         Numeric is 0
                         ;
                         ( Level > 3 ->
                              write( 'Adjusting verbosity level to = 3. ' ), nl,
                              Numeric is 3
                              ;
                              Numeric is Level
                         )
                    )
                    ;
                    fail_term( 'Unknown verbosity level. Use : true, false, 0-3' )
               )
          )
     ),
     retractall( r_verbosity_level(_) ),
     assert( r_verbosity_level(Numeric) ).

%% r_bin_version( -Version )
%
%    Get the version of R binary identified by r_bin/1. Version will have the
%    same structure as in r_session_version/1 ie M:N:F.
%
r_bin_version( Version ) :-
     r_bin( R ),
     r_bin_version( R, Version ).

%% r_bin_version( +Rbin, -Version )
%
%    Get the version of R binary identified by +Rbin. Version will have the
%    same structure as in r_session_version/1 ie M:N:F.
%
r_bin_version( R, Version ) :-
     r_bin_version_pl( R, Version ).

'<-'( X, Y ) :-
     r_in( X <- Y ).

%% settings( +Setting, +Value )
%
%    Multifile hook-predicate that allows for user settings to sip
%    through. Currently the following are recognised:
%
%       * r_open_opt
%	These come after any options given explicitly to r_open/1. For
%	example on a Mac to avoid issue with --interactive use the
%	following before querring r_open/0,1.
%
%         ==
%         :- multifile settings/2.
%         r_session:settings(r_open_opt,with(non_interactive)).
%         ==
%
%       * atom_is_r_function
%	expands atoms such as x11 to r function calls x11()
%
%       * r_function_def(+Function)
%       where Function is an R function. This hook allows default
%	argument values to R functions. Only Arg=Value pairs are
%	allowed.
%
%         ==
%         :- multifile settings/2.
%         r_session:settings(r_function_def(x11),width=5).
%         ==


%%% Section: Auxiliary predicates

% Rcv == true iff r_open_1/3 is called from recovery.
%
r_open_1( Opts, Alias, Rcv ) :-
     ssh_in_options_to_which( Opts, Host, Dir, Ssh ),
     ( (memberchk(rbin(Rbin),Opts);locate_rbin(Ssh,Rbin)) ->
          true
          ;
          fail_term( 'Use rbin/1 in r_open/n, or r_bin(\'Rbin\') or set R_BIN.' )
     ),
     r_bin_arguments( Opts, Rbin, OptRArgs, Interactive ),
     % ( var(Harg) -> RArgs = OptRArgs; RArgs = [Host,Harg|OptRArgs] ),
     ssh_conditioned_exec_and_args( Rbin, OptRArgs, Ssh, Dir, Host, Exec, Args ),
     r_verbose( r_process( Exec, Args, Ri, Ro, Re ), 3 ),
     r_process( Exec, Args, Ri, Ro, Re ),
     RStreams = r(Ri,Ro,Re),
     r_streams_set( Ri, Ro, Re ),
     r_process_was_successful( Ri, Ro, Re, Interactive ),
     r_open_opt_copy( Opts, CpOn, CpWh, Rcv ),
     r_open_opt_at_r_halt( Opts, RHalt ),
     opts_alias( Opts, Alias ),
     r_bin_version( Rbin, RbinV ),
     RData = rsdata(CpOn,CpWh,RHalt,Interactive,RbinV,Opts),
     opts_assert( Opts, Alias, RStreams, RData ),
     AtRH = at_r_halt(reinstate),
     ( (memberchk(history(false),Opts),\+memberchk(AtRH,Opts)) ->
               true
               ;
               retractall( r_session_history(Alias,_) ),
               assert( r_session_history(Alias,[]) )
     ),
     !.   % swi leaves some weird backtrack point (sometimes)

ssh_in_options_to_which( Opts, Host, Dir, Ssh ) :-
     ( options_have_ssh(Opts,Host,Dir) ->
          ( current_prolog_flag(windows,true) ->
               fail_term( ssh_option_not_supported_on_ms_windows )
               ;
               which( ssh, Ssh )
          )
          ;
          true
     ).

ssh_conditioned_exec_and_args( Rbin, OptRArgs, Ssh, Dir, Host, Exec, Args ) :-
     ( var(Ssh) ->
          Exec = Rbin, Args = OptRArgs
          ;
          Exec = Ssh,
          % atoms_concat( [' "cd ',Dir,'; ',Rbin,'"'], Harg ),
          atoms_concat( ['cd ',Dir,'; '], Cd ),
          PreArgs = [Cd,Rbin|OptRArgs],
          double_quote_on_yap( PreArgs, TailArgs ),
          Args = [Host|TailArgs]
          % atoms_concat( ['ssh ', Host,' "cd ',Dir,'; ',RBin,'"'], R )
     ).

opts_alias( Opts, Alias ) :-
     ( memberchk(alias(Alias),Opts) ->
          ( var(Alias) ->
               r_session_skolem( Alias, 1 )
               ;
               ( r_session(Alias,_,_) ->
                    fail_term( 'Session already exists for alias':Alias )
                    ;
                    true
               )
          )
          ;
          r_session_skolem( Alias, 1 )
     ).

opts_assert( Opts, Alias, RStreams, RData ) :-
     ( memberchk(assert(Assert),Opts) ->
          ( Assert == a ->
               asserta( r_session(Alias,RStreams,RData) )
               ;
               ( Assert == z ->
                    assertz( r_session(Alias,RStreams,RData) )
                    ;
                    fail_term( 'Cannot decipher argument to assert/1 option':Assert )
               )
          )
          ;
          asserta( r_session(Alias,RStreams,RData) )
     ).

r_close_session( Alias, Streams, Data ) :-
     r_streams_data( input, Streams, Ri ),
     r_streams_data( output,Streams, Ro ),
     r_streams_data( error, Streams, Re ),
     r_session_data( copy_to, Data, CopyTo ),
     r_session_data( copy_this, Data, CopyThis ),
     write( Ri, 'q()' ), nl( Ri ),
     flush_output( Ri ),
     sleep(0.25),
                  % 20101119, closing the stream straight away is probably causing
                  % problems. R goes to 100% cpu and call never terminates.
     r_record_term( CopyThis, CopyTo, 'q()' ),
     ( (CopyTo=stream(CopyS),stream_property(CopyS,file_name(CopyF)),CopyF\==user)->
          close(CopyS)
          ;
          true
     ),
     close( Ri ),
     close( Ro ),
     close( Re ),
     retractall( r_session_history(Alias,_) ).

r_in( R, RCmd, Halt ) :-
     r_push( R, RCmd, Rplc, RoLns, ReLns, Halt, HCall ),
     r_out_halted_record( Halt, R, RoLns ),
     r_lines_print( RoLns, output, user_output ),
     r_lines_print( ReLns, error, user_error ),
     r_record_history( Halt, R, RCmd ),
     replace_variables( Rplc ),
     call( HCall ),
     !.   % swi leaves some weird backtrack poionts....

r_push( R, RCmd, Rplc, RoLns, ReLns, Halt, HCall ) :-
     current_r_session( R, Streams, Data ),
     r_session_data( copy_to, Data, CopyTo ),
     r_session_data( copy_this, Data, CopyThis ),
     r_session_data( interactive, Data, Ictv ),
     r_streams( input, Streams, Ri ),
     r_streams( output, Streams, Ro ),
     r_input_normative( RCmd, R, 0, RNrm, Rplc, _ ),
     % write( wrote(RNrm) ), nl,
     write( Ri, RNrm ), nl( Ri ),
     flush_output( Ri ),
     consume_interactive_line( Ictv, _, Ro ),
     r_record_term( CopyThis, CopyTo, RNrm ),
     r_lines( Streams, error, Ictv, [], ReLns, IjErr ),
     r_halted( ReLns, R, Halt, HCall ),
     ( Halt == true ->
          r_read_lines( Ro, [], [], RoLns )
          ;
          r_lines( Streams, output, Ictv, IjErr, RoLns, [] )
     ),
     % consume_interactive_line( true, "message(\"prolog_eoc\")", Ro ),
     r_record_lines( RoLns, output, CopyTo ),
     r_record_lines( ReLns, error, CopyTo ),
     ( (Halt==true,CopyTo=stream(Cl)) -> close(Cl); true ).

r_out_halted_record( true, _Alias, [] ).
r_out_halted_record( false, _Alias, Lines ) :-
     r_session_data( copy_this, Data, CopyThis ),
     r_session_data( copy_to, Data, CopyTo ),
     ( (CopyThis==out;CopyThis==both) ->
          r_record_lines( Lines, output, CopyTo )
          ;
          true
     ).

r_flush_onto_1( [], _R, [] ).
r_flush_onto_1( [H|T], R, [HOn|TOns] ) :-
     current_r_session( R, Streams, Data ),
     r_session_data( interactive, Data, Ictv ),
     r_lines( Streams, output, Ictv, [], H, HOn ),
     % r_lines( Streams, H, HOn ),
     r_flush_onto_1( T, R, TOns ).

replace_variables( [] ).
replace_variables( [arp(R,Pv,Rv)|T] ) :-
     r_out( R, Rv, Lines ),
     r_read_obj( Lines, Pv ),
     % r_lines_to_pl_var( Lines, Pv ),
     replace_variables( T ).

% r_lines_to_pl_var( [], [] ).
% r_lines_to_pl_var( [H|T], [] ) :-
     % r_line_to_pl_var( [H|T], [] ) :-
     % r_lines_to_pl_var( T, TPv ).

r_input_streams_list( Rins ) :-
     ( select(output,Rins,NoInpIns) -> true; NoInpIns=Rins ),
     ( select(error,NoInpIns,NoErrIns) -> true; NoErrIns=NoInpIns ),
     ( NoErrIns = [] ->
          true
          ;
          ( (memberchk(input,NoErrIns);memberchk(error,NoErrIns)) ->
                    fail_term( 'duplicate entries in input streams list':Rins )
                    ;
                    fail_term( 'superfluous entries in input streams list':Rins )
          )
     ).

% succeds if Rcmd produces empty output, otherwise it fails
ro_empty( R, Rcmd ) :-
     r_out( R, Rcmd, [] ).

r_input_normative( (A;B), R, I, This, Rplc, OutI ) :-
     !,
     r_input_normative( A, R, I, ThisA, RplcA, NxI ),
     r_input_normative( B, R, NxI, ThisB, RplcB, OutI ),
     atoms_concat( [ThisA,'; ',ThisB], This ),
     append( RplcA, RplcB, Rplc ).

% r_input_normative( Obj<-List, _R, I, This, Rplc, NxI ) :-
     % % atomic( Obj ),
     % is_list( List ),
     % !,
     % Rplc = [],
     % NxI is I,
     % pl_list_to_r_combine( List,

r_input_normative( Obj<-Call, R, I, This, Rplc, NxI ) :-
     !,
     ( var(Obj) ->
          Rplc = [arp(R,Obj,ThisObj)],
          atomic_list_concat([pl_Rv_, I], ThisObj),
          NxI is I + 1
          ;
          Rplc = [],
          r_input_normative( Obj, ThisObj ),
          NxI is I
     ),
     r_input_normative( Call, ThisCall ),
     atoms_concat( [ThisObj,' <- ',ThisCall], This ).
r_input_normative( PrvThis, _R, I, This, [], I ) :-
     r_input_normative( PrvThis, This ).

r_input_normative( Var, This ) :-
     var(Var),
     !,
     This = Var.
r_input_normative( Opt=Val, This ) :-
     !,
     r_input_normative( Opt, ThisOpt ),
     r_input_normative( Val, ThisVal ),
     atoms_concat( [ThisOpt,'=',ThisVal], This ).
% 2008ac06, careful! we are changing behaviour here
r_input_normative( List, This ) :-
     is_list( List ),
     pl_list_to_r_combine( List, This ),
     !.
r_input_normative( PrvThis, This ) :-
     ( (\+ var(PrvThis),(PrvThis = [_|_];PrvThis=[])) ->
          append( PrvThis, [0'"], ThisRight ),
          atom_codes( This, [0'"|ThisRight] )
          ;
          ( compound(PrvThis) ->
               PrvThis =.. [Name|Args],
               ( (current_op(_Pres,Asc,Name),
                  atom_codes(Asc,[_,0'f,_]),
                  Args = [Arg1,Arg2]
               ) ->
                    r_input_normative( Arg1, Arg1Nrm ),
                    r_input_normative( Arg2, Arg2Nrm ),
                    atoms_concat( [Arg1Nrm,Name,Arg2Nrm], This )
                    ;
                    r_function_has_default_args( Name, Defs ),
                    cohese_r_function_args( Args, Defs, AllArgs ),
                    r_input_normative_tuple( AllArgs, Tuple ),
                    atoms_concat( [Name,'(',Tuple,')'], This )
               )
               ;
               ( number(PrvThis) ->
                    number_codes( PrvThis, ThisCs ),
                    atom_codes( This, ThisCs )
                    ;
                    ( ( atom_concat(Name,'()',PrvThis) ;
                         (settings(atom_is_r_function,PrvThis),Name=PrvThis) )
                              ->
                              r_function_has_default_args_tuple( Name, Tuple ),
                              ( Tuple \== '' ->
                                   atoms_concat( [Name,'(',Tuple,')'], This )
                                   ;
                                   This = PrvThis
                              )
                         ;
                         This = PrvThis
                    )
               )
          )
     ).

r_function_has_default_args_tuple( This, Tuple ) :-
     r_function_has_default_args( This, Args ),
     r_input_normative_tuple( Args, Tuple ).

r_function_has_default_args( This, Flat ) :-
     findall( A, r_session:settings(r_function_def(This),A), Args ),
     flatten( Args, Flat ).

r_input_normative_tuple( [], '' ).
r_input_normative_tuple( [H|T], Tuple ) :-
     r_input_normative_tuple( T, Psf ),
     r_input_normative( H, HNorm ),
     ( Psf == '' -> Tuple = HNorm
        ; atoms_concat([HNorm,',',Psf], Tuple) ).

pl_list_to_r_combine( [H|T], This ) :-
     number_atom_to_atom( H, Hatm ),
     atom_concat( 'c(', Hatm, Pfx ),
     pl_list_to_r_combine( T, Pfx, This ).

pl_list_to_r_combine( [], Pfx, This ) :-
     atom_concat( Pfx, ')', This ).
pl_list_to_r_combine( [H|T], Pfx, This ) :-
     number_atom_to_atom( H, Hatm ),
     atom_concat( Pfx, ',', PfxComma ),
     atom_concat( PfxComma, Hatm, Nxt ),
     pl_list_to_r_combine( T, Nxt, This ).

number_atom_to_atom( NorA, Atom ) :-
     number_atom_to_codes( NorA, Codes ),
     atom_codes( Atom, Codes ).

number_atom_to_codes( NorA, Codes ) :-
     number( NorA ),
     !,
     number_codes( NorA, Codes ).
number_atom_to_codes( NorA, Codes ) :-
     atom( NorA ),
     !,
     atom_codes( NorA, Codes ).

r_read_lines( Ro, Ij, TermLine, Lines ) :-
     read_line_to_codes( Ro, Line ),
     r_read_lines_1( Line, TermLine, Ij, Ro, Lines ).

r_halted( Lines, R, Halted, HCall ) :-
     last( Lines, "Execution halted" ),
     !,
     Halted = true,
     findall( rs(Alias,Streams,Data), retract(r_session(Alias,Streams,Data)), Sessions),
     \+ var(R),
     r_halted_recovery( Sessions, R, HCall ).
r_halted( _, _R, false, true ).

r_halted_recovery( [], R, Which ) :-
     ( var(Which) ->
          fail_term( internal_error_in_recovering_from_halt(R) )
          ;
          true
     ).
r_halted_recovery( [rs(AliasH,StreamsH,DataH)|T], R, Which ) :-
     ( R == AliasH ->
          r_session_data( at_r_halt, DataH, AtHalt ),
          r_halted_recovery_action( AtHalt, AliasH, StreamsH, DataH, Which )
          ;
          assertz(r_session(AliasH,StreamsH,DataH))
     ),
     r_halted_recovery( T, R, Which ).

r_halted_recovery_action( restart, Alias, _Streams, Data, RecCall ) :-
     Mess = 'at_r_halt(restart): restarting r_session ':Alias,
     RecCall = (write( user_error, Mess ),nl( user_error )),
     r_session_data( opts, Data, Opts ),
     ( memberchk(copy(CopyTo,_),Opts) ->
          r_halted_restart_copy(CopyTo)
          ;
          true
     ),
     r_open_1( Opts, Alias, true ),
     current_r_session( Alias, Streams, Data ),
     r_session_data( interactive, Data, Ictv ),
     r_lines( Streams, output, Ictv, [], _H, _ ).
     % r_lines( Streams, output, _ReLines ).
r_halted_recovery_action( reinstate, Alias, _Streams, Data, RecCall ) :-
     ( r_session_history(Alias,History) ->
          r_session_data( opts, Data, Opts ),
          r_open_1( Opts, Alias, true ),
          reverse( History, Hicory ),
          r_halted_recovery_rollback( Hicory, Alias )
          ;
          fail_term( 'at_r_halt(reinstate): cannnot locate history for':Alias )
     ),
     Mess = 'at_r_halt(reinstate): reinstating r_session ':Alias,
     RecCall = (write( user_error, Mess ), nl( user_error ) ).
r_halted_recovery_action( abort, _Alias, _Streams, _Data, RecCall ) :-
     Mess = 'at_r_halt(abort): R session halted by slave',
     RecCall = (write( user_error, Mess ),nl( user_error ),abort).
r_halted_recovery_action( fail, Alias, _Streams, _Data, Call ) :-
     retractall( r_session_history(Alias,_) ),
     % % r_session_data( copy_to, Data, CopyTo ),
     % write( copy_to(CopyTo) ), nl,
     % ( CopyTo = stream(Stream) ->
          % close(Stream)
          % ;
          % true
     % ),
     L='at_r_halt(fail): failure due to execution halted by slave on r_session',
     Call = fail_term( L:Alias ).
r_halted_recovery_action( call(Call), _Alias, Streams, _Data, Call ) :-
     Call = call( Call, Streams ).
r_halted_recovery_action( call_ground(Call), _Alias, _Streams, _Data, Call) :-
     Call = call( Call ).

r_halted_restart_copy( CopyTo ) :-
     ((atomic(CopyTo),File=CopyTo);CopyTo=once(File)),
     File \== user,      % you never known
     !,
     open( File, read, Dummy ),
     stream_property( Dummy, file_name(Full) ),
     close( Dummy ),
     ( stream_property(OpenStream,file_name(Full)) ->
          write( close(OpenStream) ), nl,
          close( OpenStream )
          ;
          true
     ).
r_halted_restart_copy( _CopyTo ).

r_halted_recovery_rollback( [], _Alias ).
r_halted_recovery_rollback( [H|T], Alias ) :-
     r_in( Alias, H, _Halted ),
     r_halted_recovery_rollback( T, Alias ).


r_record_history( true, _Alias, _This ).
r_record_history( false, Alias, This ) :-
     r_session_history( Alias, Old ),
     !,
     retractall( r_session_history(Alias,_) ),
     assert( r_session_history(Alias,[This|Old]) ).
r_record_history( false, _, _ ). % fold with true if assumption is correct

r_read_lines_1( eof, _TermLine, Ij, _Ro, Lines ) :-
     !,
     interject_error( Ij ),
     Lines = [].
r_read_lines_1( end_of_file, _TermLine, _Ij, _Ro, Lines ) :- !, Lines = [].
r_read_lines_1( [255], _TermLine, _Ij, _Ro, Lines ) :- !, Lines = [].
     % yap idiosyncrasy
r_read_lines_1( TermLine, TermLine, Ij, _Ro, Lines ) :-
     !,
     interject_error( Ij ),
     Lines = [].
r_read_lines_1( Line, TermLine, Ij, Ro, Lines ) :-
     ( select(Line,Ij,RIj) ->
          % atom_codes(Atom,Line),write( skipping_diagnostic(Atom) ), nl,
          Lines = TLines,
          read_line_to_codes( Ro, NewLine )
          ;
          RIj = Ij,
          read_line_to_codes( Ro, NewLine ),
          Lines = [Line|TLines]
     ),
     r_read_lines_1( NewLine, TermLine, RIj, Ro, TLines ).

interject_error( [] ).
interject_error( [H|T] ) :-
     findall( X, (member(X,[H|T]),write(x(X)),nl), Xs ),
     length( Xs, L ),
     fail_term( above_lines_not_found_in_output(L) ).

r_boolean( Boo, Rboo ) :-
     ( memberchk(Boo,[t,true,'TRUE']) ->
          Rboo = 'TRUE'
          ;
          memberchk(Boo,[f,false,'FALSE']),
          Rboo = 'FALSE'
     ).

/* r_read_obj( Lines, Pv ) :-
     In X <- x  read R object x into prolog variable X.
     Currently recognizes [[]] lists, matrices and vectors.
     */
r_read_obj( [L|Ls], Pv ) :-
     r_head_line_recognizes_and_reads( L, Ls, Pv ).

% list
r_head_line_recognizes_and_reads( [0'[,0'[|T], Ls, Pv ) :-
     !,
     break_list_on( T, 0'], Lname, RList ),
     RList = [0']],   % do some error handling here
     % break_list_on( Ls, [], Left, Right ),
     r_read_obj_nest( Ls, Nest, Rem ),
     name( K, Lname ),
     Pv = [K-Nest|Rest],
     r_read_list_remainder( Rem, Rest ).
% vector
r_head_line_recognizes_and_reads( Line, Ls, Pv ) :-
     delete_leading( Line, 0' , NeLine ),
     NeLine = [0'[|_],
     !,
     r_read_vect( [NeLine|Ls], PvPrv ),
     ( PvPrv = [Pv] -> true; Pv = PvPrv ).
% matrix
% r_head_line_recognizes_and_reads( [0' ,0' ,0' ,0' ,0' |T], Ls, Pv ) :-
r_head_line_recognizes_and_reads( [0' |T], Ls, Pv ) :-
     % Five = [0' ,0' ,0' ,0' ,0' |T1],
     r_read_vect_line( T, Cnames, [] ),
     ( break_list_on(Ls,[0' |T1],Left,Right) ->
          % maybe we can avoid coming here, this terminal has no width restriction...
          read_table_section( Left, Rnames, Entries ),
          r_head_line_recognizes_and_reads( [0' |T1], Right, PvT ),
          % do loads of error checking from here on
          clean_up_matrix_headers( Rnames, NRnames ),
          PvT = tbl(NRnames,CnamesR,MatR),
          append_matrices_on_columns( Entries, MatR, Mat ),
          append( Cnames, CnamesR, CnamesAll ),
          clean_up_matrix_headers( CnamesAll, NCnamesAll ),
          Pv = tbl(NRnames,NCnamesAll,Mat)

          % r_read_vect( T1, Cnames2 ),
          % read_table_sections( Right, Rnames, Cnames, Cnames2, T1, _HERE,  Ls, Pv )
          ;
          read_table_section( Ls, Rnames, Entries ),
          clean_up_matrix_headers( Rnames, NRnames ),
          clean_up_matrix_headers( Cnames, NCnames ),
          Pv = tbl(NRnames,NCnames,Entries)
     ).

r_read_obj_nest( Ls, Nest, Rem ) :-
     break_list_on( Ls, [], Left, Rem ),
     r_read_obj( Left, Nest ).

r_read_vect( [], [] ).
r_read_vect( [PreH|T], List ) :-
     delete_leading( PreH, 0' , H ),
     ( H = [0'[|Hrm] ->
          break_list_on( Hrm, 0'], _, Hprv ),
          delete_leading( Hprv, 0' , Hproper )
          ;
          Hproper = H
     ),
     r_read_vect_line( Hproper, List, ConTail ),
     r_read_vect( T, ConTail ).

r_read_vect_line( [], List, List ).
r_read_vect_line( [0' |RRead], List, ConTail ) :-
     !,
     r_read_vect_line( RRead, List, ConTail ).
r_read_vect_line( [Fst|RRead], [H|List], ConTail ) :-
     break_list_on( RRead, 0' , RemCs, RemNumCs ),
     !,
     % number_codes( H, [Fst|RemCs] ),
     name( H, [Fst|RemCs] ),
     r_read_vect_line( RemNumCs, List, ConTail ).
r_read_vect_line( [Fst|RemCs], [H|List], List ) :-
     name( H, [Fst|RemCs] ).
     % number_codes( H, [Fst|RemCs] ).

r_read_list_remainder( [], [] ).
r_read_list_remainder( [H|T], Rest ) :-
     H = [0'[,0'[|_],
     r_head_line_recognizes_and_reads( H, T, Rest ).

read_table_section( [], [], [] ).
read_table_section( [L|Ls], [H|Hs], [Es|TEs] ) :-
     r_read_vect_line( L, [H|Es], [] ),
     read_table_section( Ls, Hs, TEs ).

clean_up_matrix_headers( [], [] ).
clean_up_matrix_headers( [H|T], [F|R] ) :-
     ( (atom_concat('[',X,H),atom_concat(Y,',]',X)) ->
          atom_codes( Y, YCs ),
          number_codes( F, YCs )
          ;
          ( (atom_concat('[,',X,H),atom_concat(Y,']',X)) ->
               atom_codes( Y, YCs ),
               number_codes( F, YCs )
               ;
               F=H
          )
     ),
     clean_up_matrix_headers( T, R ).

append_matrices_on_columns( [], [], [] ).
append_matrices_on_columns( [H1|T1], [H2|T2], [H3|T3] ) :-
     append( H1, H2, H3 ),
     append_matrices_on_columns( T1, T2, T3 ).

r_streams( [], _R, [] ).
r_streams( [H|T], R, [SH|ST] ) :-
     !,
     r_stream( H, R, SH ),
     r_streams( T, R, ST ).

r_streams( Id, R, Stream ) :-
     r_stream( Id, R, Stream ).

r_stream( H, R, SH ) :-
     % current_r_session( R ),
     ( var(H) ->
          fail_term( variable_stream_identifier )
          ;
          true
     ),
     ( r_streams_data( H, R, SH ) ->
          true
          ;
          fail_term( invalid_r_stream:H )
     ).

/*
r_terminator( r(Ri,Ro,_Re), Lines ) :-
     write( Ri, 'print(\"prolog_eoc\")' ),
     nl( Ri ),
     r_read_lines_till( Ro, "[1] \"prolog_eoc\"", Lines ).

r_read_lines_till( Ro, Terminator, Lines ) :-
     fget_line( Ro, Line ),
     r_read_lines_till_1( Line, Terminator, Ro, Lines ).

r_read_lines_till_1( Line, Line, _Ro, Lines ) :-
     !,
     Lines = [].
r_read_lines_till_1( Line, Terminator, Ro, [Line|Lines] ) :-
     fget_line( Ro, NxLine ),
     NxLine \== eof,
     r_read_lines_till_1( NxLine, Terminator, Ro, Lines ).
*/

r_open_opt_copy( Opts, CpTerm, What, Rcv ) :-
     ( (memberchk(copy(Cp,CpWh),Opts),Cp \== null) ->
          % heere
          ( ((catch(is_stream(Cp),_,fail),CpS=Cp);Cp=stream(CpS)) ->  % catch = yap bug
               CpTerm = stream(CpS)
               ;
               ( atomic(Cp) ->
                    ( Rcv==true -> Mode = append; Mode = write ),
                    open( Cp, Mode, CpStream ),
                    CpTerm = stream(CpStream)
                    ;
                    ( Cp = once(CpFile) ->
                         ( Rcv==true -> Mode = append; Mode = write ),
                         open( CpFile, Mode, CpStream ),
                         CpTerm = stream(CpStream)
                         ;
                         ( Cp = many(CpFile) ->
                              CpTerm = file(CpFile)
                              ;
                              fail_term( 'I cannot decipher 1st argument of copy/2 option':Cp )
                         )
                    )
               )
          ),
          ( memberchk(CpWh,[both,none,in,out])->
               What = CpWh
               ;
               fail_term( 'I cannot decipher 2nd arg. to copy/2 option':CpWh )
          )
          ;
          CpTerm = null, What = none
     ).

r_open_opt_at_r_halt( Opts, RHalt ) :-
     ( memberchk(at_r_halt(RHalt),Opts) ->
          Poss = [restart,reinstate,fail,abort,call(_),call_ground(_)],
          ( memberchk(RHalt,Poss) ->
               true
               ;
               fail_term( 'Cannot decipher argument to at_r_halt option':RHalt )
          )
          ;
          RHalt = fail
     ).

r_bin_arguments( Opts, _Rbin, _RArgs ) :-
     member( with(With), Opts ),
     \+ memberchk(With, [environ,non_interactive,restore,save] ),
     !,
     fail_term( 'Cannot decipher argument to option with/1': With ).
r_bin_arguments( Opts, _Rbin, Args, Interactive ) :-
     ( current_prolog_flag(windows,true) ->
          Args = ['--ess','--slave'|RArgs],
          Interactive = false,
          NonIOpts = Opts
          ; % assuming unix here, --interactive is only supported on these
          /*
          decided to scrap this, is still accessile via option with/1
          ( r_bin_takes_interactive(Rbin) ->
               Args = ['--interactive','--slave'|RArgs]
               ;
               Args = ['`--slave'|RArgs]
          )
          */
          ( select(with(non_interactive),Opts,NonIOpts) ->
               Args = ['--slave'|RArgs],
               Interactive = false
               ;
               NonIOpts = Opts,
               Args = ['--interactive','--slave'|RArgs],
               Interactive = true
          )
     ),
     findall( W, member(with(W),NonIOpts), Ws ),
     sort( Ws, Sr ),
     length( Ws, WsL ),
     length( Sr, SrL ),
     ( WsL =:= SrL ->
          r_bin_arguments_complement( [environ,restore,save], Ws, RArgs )
          ;
          fail_term( 'Multiple identical args in with/1 option': Ws )
     ).

% r_opt_exec_no( [environ,restore,save], Ws, Pfx, Exec ) :-
r_opt_exec_no( [], _Ws, [] ).
r_opt_exec_no( [H|T], Ws, Exec ) :-
     ( memberchk(H,Ws) ->
          TExec=Exec
          ;
          atom_concat( '--no-', H, NoH ),
          Exec=[NoH|TExec]
     ),
     r_opt_exec_no( T, Ws, TExec ).

r_bin_arguments_complement( [], Ws, [] ) :-
     ( Ws == [] ->
          true
          ;
          write( user_error, unrecognized_with_opts(Ws) ),
          nl( user_error )
     ).
r_bin_arguments_complement( [H|T], Ws, Args ) :-
     ( memberchk(H,Ws) ->
          Args = TArgs
          ;
          atom_concat( '--no-', H, NoH ),
          Args = [NoH|TArgs]
     ),
     r_bin_arguments_complement( T, Ws, TArgs ).

r_record_lines( [], _Type, _CopyTo ) :- !.
r_record_lines( Lines, Type, CopyTo ) :-
     ( CopyTo == null ->
          true
          ;
          copy_stream_open( CopyTo, CopyStream ),
          r_lines_print( Lines, Type, CopyStream )
     ).

r_record_term( CopyThis, CopyTo, This ) :-
     ( CopyThis == in; CopyThis == both),
     CopyTo \== null,
     !,
     copy_stream_open( CopyTo, CopyOn ),
     write( CopyOn, This ),
     nl( CopyOn ),
     copy_stream_close( CopyTo ).
r_record_term( _CopyThis, _CopyTo, _This ).

copy_stream_open( stream(CopyStream), CopyStream ).
copy_stream_open( file(File), CopyStream ) :-
     open( File, append, CopyStream ).

copy_stream_close( Atom ) :-
     atomic( Atom ),
     !,
     ( Atom == user ->
          true
          ;
          close( Atom )
     ).
copy_stream_close( CopyTo ) :-
     copy_stream_close_non_atomic( CopyTo ).

copy_stream_close_non_atomic( file(CopyTo) ) :- close( CopyTo ).
copy_stream_close_non_atomic( once(CopyTo) ) :- close( CopyTo ).
copy_stream_close_non_atomic( many(CopyTo) ) :- close( CopyTo ).
copy_stream_close_non_atomic( stream(_) ).

/*
write_list_to_comma_separated( [], _Sep, _Out ).
write_list_to_comma_separated( [H|T], Sep, Out ) :-
     write( Out, Sep ),
     write( Out, H ),
     write_list_to_comma_separated( T, ',', Out ).
     */

fail_term( Term ) :-
     ( Term = What:Which ->
          write( user_error, What ),
          write( user_error, ': ' ),
          write( user_error, Which )
          ;
          write( user_error, Term )
     ),
     nl( user_error ), fail.

r_lines( Streams, ROstream, Interactive, InJ, Lines, ToInterj ) :-
     r_streams_data( input,  Streams, Ri ),
     r_streams_data( ROstream,  Streams, Ro ),
     ( ROstream == error ->
          Mess = 'message("prolog_eoc")',
          Trmn = "prolog_eoc",
          r_streams_data( output,  Streams, _Ruo ),
          AllIj = InJ
          ;
          Mess = 'print("prolog_eoc")',
          Trmn = "[1] \"prolog_eoc\"",
          ( Interactive == true ->
               append( InJ, ["print(\"prolog_eoc\")"], AllIj )
               ;
               AllIj = InJ
          )
     ),
     Excp = error(io_error(write, _), context(_,_)),
     catch( (write(Ri,Mess),nl(Ri),flush_output(Ri)), Excp, true ),
     atom_codes( Mess, MessLine ),
     r_read_lines( Ro, AllIj, Trmn, Lines ),
     % read_line_to_codes( Ro, Line ), atom_codes( AtLine, Line ), atom_codes( AtTrmn, Trmn ),
     % write( nxt_was(AtLine,AtTrmn) ), nl,
     ( (Interactive == true, ROstream == error) ->
               ToInterj = [MessLine]
               ;
               % consume_interactive_line( true, MessLine, Ruo ),
               ToInterj = []
     ).

r_lines_print_type_stream( output, user_output ).
r_lines_print_type_stream( error, user_error ).

r_lines_print_prefix( error, Stream ) :- write( Stream, '!  ' ).
r_lines_print_prefix( output, _Stream ).

r_session_skolem( Alias, I ) :-
     Alias = '$rsalias'(I),
     \+ r_session( Alias, _, _ ),
     !.
r_session_skolem( Alias, I ) :-
     NxI is I + 1,
     r_session_skolem( Alias, NxI ).

r_process_was_successful( Ri, Ro, Re, Interactive ) :-
     Mess = 'message("prolog_eoc")',
     Trmn = "prolog_eoc",
     catch( (write(Ri,Mess),nl(Ri),flush_output(Ri)), Excp, true ),
     r_read_lines( Re, [], Trmn, Lines ),
     consume_interactive_line( Interactive, Mess, Ro ),
     r_lines_print( Lines, error, user_error ),
     ( (var(Excp),Lines==[]) ->
          true
          ;
          ( Excp = error(io_error(write, _), context(_,_)) ->
               true
               ;
               print_message( error, Excp )
          ),
          close( Ri ), close( Ro ), close( Re ),
          fail_term( failed_to_open_session )
     ).

%%%%%%%%
% break_list_on( +List, +Element, ?LeftPartition, ?RightPartition ).
% Element does not appear in either the end of LeftPartition,
% or as first element of RightPartition.
% Only finds first partition so Element should be ground
% | ?- break_list_on( L, El, [a], [c,b,d,b,e] ).
%  = [a,El,c,b,d,b,e] ? ; no
%
break_list_on( [X|Xs], X, [], Xs ) :-
	!.
break_list_on( [X|Xs], Xa, [X|XLa], XRa ) :-
	break_list_on( Xs, Xa, XLa, XRa ).

delete_leading( [], _Chop, [] ).
delete_leading( [H|T], Chop, Clean ) :-
     ( H == Chop ->
          R = T,
          Clean = TClean
          ;
          R = [],
          Clean = [H|T]
     ),
     delete_leading( R, Chop, TClean ).

options_have_ssh( Opts, Host, Dir ) :-
     ( memberchk(ssh(Host),Opts) ->
          Dir = '/tmp'
          ;
          memberchk( ssh(Host,Dir), Opts )
     ).

locate_rbin( Ssh, RBin ) :-
     locate_rbin_file( File ),
     ( var(Ssh) ->
          ( current_prolog_flag(windows,true),
               ( atom_concat(_,exe,File) ->
                    RBin = File         % this if and its then part are only needed because
                                        % currrent Yap implementation is broken
                    ;
                    file_name_extension( File, exe, RBin )
               )
               ;
               RBin = File
          ),
          exists_file( RBin )
          ;
          % currently when we using ssh, there is no check for existance
          % of the binary on the remote host
          File = RBin
     ),
     r_verbose( using_R_bin(RBin), 1 ).

% order of clauses matters. only first existing one to succeed is considered.
locate_rbin_file( RBin ) :-
     % current_predicate( r_bin/1 ),
     r_bin_location( RBin ).
locate_rbin_file( RBin ) :-
     environ( 'R_BIN', RBin ).
locate_rbin_file( RBin ) :-
     current_prolog_flag( unix, true ),
     which( 'R', RBin ).
locate_rbin_file( RBin ) :-
     current_prolog_flag( windows, true ),
     r_bin_wins( RBin ).

r_bin_wins( Rbin ) :-
     r_expand_wins_rterm( Stem, Candidates ),
     r_verbose( wins_candidates(Candidates), 3 ),
     Candidates \== [],
     ( Candidates = [Rbin] ->
          true
          ;
          maplist( atom_concat(Stem), Tails, Candidates ),
          maplist( atom_codes, Tails, TailsCs ),
          cur_tail_candidates_with_pair( TailsCs, Candidates, Pairs ),
          keysort( Pairs, Sorted ),
          reverse( Sorted, [_-Rbin|_] )
     ),
     !.

cur_tail_candidates_with_pair( [], [], [] ).
cur_tail_candidates_with_pair( [H|T], [F|R], [Hnum-F|TPairs] ) :-
     ( break_list_on( H, 0'/, Hlft, _ ) -> true; break_list_on( H, 0'\\, Hlft, _) ),
     break_list_on( Hlft, 0'., MjCs, NonMjCs ),
     break_list_on( NonMjCs, 0'., MnCs, FxCs ),
     maplist( number_codes, Nums, [MjCs,MnCs,FxCs] ),
     integers_list_to_integer( Nums, 2, 1000, 0, Hnum ),
     cur_tail_candidates_with_pair( T, R, TPairs ).

integers_list_to_integer( [], _Pow, _Spc, Int, Int ).
integers_list_to_integer( [H|T], Pow, Spc, Acc, Int ) :-
     Nxt is Acc + ( H * (Spc ** Pow) ),
     Red is Pow - 1,
     integers_list_to_integer( T, Red, Spc, Nxt, Int ).

r_bin_warning :-
     write('Flag --interactive which is used when starting R sessions,'),
     nl,
     write( 'is not behaving as expected on your installed R binary.' ), nl,
     write( 'R sessions with this binary will be started without this flag.' ),
     nl,
     write( 'As a result, graphic windows will suffer and the connection is' ),
     write( ' more flaky.' ), nl,
     write( 'If you want to overcome these limitations we strongly suggest' ),
     nl,
     write( 'the installation of R from sources.' ), nl, nl.

r_bin_takes_interactive( Rbin ) :-
     r_bin_takes_interactive( Rbin, Bool ),
     !,
     Bool == true.
r_bin_takes_interactive( Rbin ) :-
     Args = ['--interactive','--slave','--no-environ','--no-restore','--no-save'],
     r_process( Rbin, Args, Ri, Ro, Re ),
     r_streams_set( Ri, Ro, Re ),
     % Streams = r(Ri,Ro,Re),
     write( Ri, 'print("whatever")' ), nl( Ri ),
     flush_output( Ri ),
     % r_read_lines( Re, eof, RoLns ),
     % read_line_to_codes( Re, _ReLns ),
     % r_lines( Streams, error, ReLns ),
     % r_lines( Streams, output, RoLns ),
     read_line_to_codes( Ro, RoLn ),
     ( append("print", _, RoLn ) ->
          r_bin_warning,
          Bool = false
          ;
          Bool = true
     ),
     assert( r_bin_takes_interactive(Rbin,Bool) ),
     write( Ri, 'q()' ), nl( Ri ),
     flush_output( Ri ),
     read_line_to_codes( Re, _ReLn ),
     % write( Ri, 'message("whatever")' ), nl( Ri ),
     close( Ri ), close( Ro ), close( Re ),
     Bool == true.

consume_interactive_line( true, Line, Rstream ) :-
     read_line_to_codes( Rstream, Codes ),
     atom_codes( Found, Codes ),
     % ( var(Line) -> write( consuming_var(Found) ), nl; true ),
     ( Found = Line ->
          true
          ;
          fail_term(could_not_conusme_specific_echo_line(Line)-Found )
     ).
consume_interactive_line( false, _, _ ).

cohese_r_function_args( [], Defs, Defs ).
cohese_r_function_args( [H|T], Defs, [H|R] ) :-
     ( (\+ var(H), H = (N=_V),select(N=_V1,Defs,RemDefs)) ->
               true
               ;
               RemDefs = Defs
     ),
     cohese_r_function_args( T, RemDefs, R ).
% Section: Swi Specifics.

/*
r_lines( Streams, ROstream, Lines ) :-
     r_streams_data( input,  Streams, Ri ),
     r_streams_data( ROstream,  Streams, Ro ),
     ( ROstream == error ->
          Mess = 'message("prolog_eoc")',
          Trmn = "prolog_eoc"
          ;
          Mess = 'print("prolog_eoc")',
          Trmn = "[1] \"prolog_eoc\""
     ),
     Excp = error(io_error(write, _), context(_,_)),
     catch( (write(Ri,Mess),nl(Ri)), Excp, true ),
     r_read_lines( Ro, Trmn, Lines ).
     */

atoms_concat( Atoms, Concat ) :-
     atomic_list_concat( Atoms, Concat ).

which( Which, This ) :-
     absolute_file_name( path(Which), This,
			 [ extensions(['',exe]),
			   access(exist)
			 ]),
     r_verbose( which(Which,This), 2 ).

r_streams_set( Ri, Ro, Re ) :-
     set_stream( Ri, buffer(false) ), set_stream( Ri, close_on_abort(true) ),
     set_stream( Ro, buffer(false) ), set_stream( Ro, close_on_abort(true) ),
     set_stream( Re, buffer(false) ), set_stream( Re, close_on_abort(true) ).

r_process( R, Args, Ri, Ro, Re ) :-
     Streams = [stdin(pipe(Ri)),stdout(pipe(Ro)),stderr(pipe(Re))],
     process_create( R, Args, Streams ),
     r_verbose( created(R,Args,Streams), 3 ).

r_bin_version_pl( R, Vers ) :-
     Streams = [stdout(pipe(Ro))],
     r_bin_version_pl_stream( R, Streams, Ro, Vers ),
     !.
%  2:12:1 on windows talks to error... :(
r_bin_version_pl( R, Vers ) :-
     Streams = [stderr(pipe(Ro))],
     r_bin_version_pl_stream( R, Streams, Ro, Vers ).

r_bin_version_pl_stream( R, Streams, Ro, Mj:Mn:Fx ) :-
     process_create( R, ['--version'], Streams ),
     % read_line_to_codes( Ro, _ ),
     read_line_to_codes( Ro, Codes ),
     break_list_on( Codes, 0' , _R, Psf1 ),
     break_list_on( Psf1, 0' , _V, Psf2 ),
     break_list_on( Psf2, 0' , VersionCs, _ ),
     break_list_on( VersionCs, 0'., MjCs, VPsf1Cs ),
     break_list_on( VPsf1Cs, 0'., MnCs, FxCs ),
     number_codes( Mj, MjCs ),
     number_codes( Mn, MnCs ),
     number_codes( Fx, FxCs ).

r_expand_wins_rterm( Stem, Candidates ) :-
     Stem = 'C:/Program Files/R/R-',
     Psfx = '*/bin/Rterm.exe',
     atom_concat( Stem, Psfx, Search ),
     expand_file_name( Search, Candidates1 ),
     % on 64 bit machines Rterm.exe is placed in subdir R-1.12.1
     Psfx2= '*/bin',
     atom_concat( Stem, Psfx2, SearchBin ),
     expand_file_name( SearchBin, BinFolders ),
     findall( CandidateList, (
                                   member(Bin,BinFolders),
                                   atom_concat( Bin, '/*/Rterm.exe', NestSearch ),
                                   expand_file_name( NestSearch, CandidateList )
                              ),
                                        NestedCandidates ),
     flatten( [Candidates1|NestedCandidates], Candidates ).

environ( Var, Val ) :-
     \+ var(Var),
     ( var(Val) ->
          getenv(Var,Val)
          ;
          setenv(Var,Val)
     ).

double_quote_on_yap( A, A ).
