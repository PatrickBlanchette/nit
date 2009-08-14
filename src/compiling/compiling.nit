# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2008 Jean Privat <jean@pryen.org>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Compute and generate tables for classes and modules.
package compiling

import compiling_base
private import compiling_global
private import compiling_icode

redef class MMModule
	# Compile the program
	# Generate all sep files (_sep.[ch]), the main file (_table.c) and the build file (_build.sh)
	# Then execute the build.sh
	fun compile_prog_to_c(tc: ToolContext)
	do
		tc.info("Building tables",1)
		for m in mhe.greaters_and_self do
			tc.info("Building tables for module: {m.name}",2)
			m.local_analysis(tc)
		end

		tc.info("Merging all tables",2)
		var ga = global_analysis(tc)

		tc.compdir.mkdir

		var files = new Array[String]
		var includes = new ArraySet[String]
		files.add("$CLIBDIR/nit_main.c")
		files.add("$CLIBDIR/gc.c")
		files.add("$CLIBDIR/gc_static_objects_list.c")
		tc.info("Generating C code",1)
		for m in mhe.greaters_and_self do
			files.add("{tc.compdir}/{m.name}._sep.c")
			tc.info("Generating C code for module: {m.name}",2)
			m.compile_separate_module(tc, ga)
			var native_name = m.location.file.strip_extension(".nit")
			if (native_name + "_nit.h").file_exists then
				includes.add("-I {native_name.dirname}")
			end
			native_name += "_nit.c"
			if native_name.file_exists then files.add(native_name)
		end

		tc.info("Generating main, tables and makefile ...",1)
		files.add("{tc.compdir}/{name}._tables.c")
		compile_main(tc, ga)

		var fn = "{tc.compdir}/{name}._build.sh"
		var f = new OFStream.open(fn)
		var verbose = ""

		if tc.verbose_level > 0 then
			verbose = "-"
			for i in [1..tc.verbose_level] do verbose = verbose + "v"
		end

		f.write("#!/bin/sh\n")
		f.write("# This shell script is generated by NIT to compile the program {name}.\n")
		f.write("CLIBDIR=\"{tc.clibdir}\"\n")
		f.write("{tc.bindir}/gccx {verbose} -d {tc.compdir} -I $CLIBDIR {includes.join(" ")}")
		if tc.output_file != null then 
			f.write(" -o {tc.output_file}")
		else if tc.ext_prefix.is_empty then
			f.write(" -o {name}")
		else
			f.write(" -o {name}_{tc.ext_prefix}")
		end
		if tc.boost then f.write(" -O")
		f.write(" \"$@\" \\\n  {files.join("\\\n  ")}\n")
		f.close

		if not tc.no_cc then 
			tc.info("Building",1)
			sys.system("sh {fn}")
		end
	end

	# Compile the main file
	private fun compile_main(tc: ToolContext, ga: GlobalAnalysis)
	do
		var v = new GlobalCompilerVisitor(self, tc, ga)
		v.add_decl("#include <nit_common.h>")
		compile_tables_to_c(v)
		compile_main_part(v)
		var f = new OFStream.open("{tc.compdir}/{name}._tables.c")
		f.write("/* This C file is generated by NIT to compile program {name}. */\n")
		for m in mhe.greaters_and_self do
			f.write("#include \"{m.name}._sep.h\"\n")
		end
		f.write(v.to_s)
		f.close
	end

	# Compile the sep files (of the current module only)
	private fun compile_separate_module(tc: ToolContext, ga: GlobalAnalysis)
	do
		var v = new GlobalCompilerVisitor(self, tc, ga)
		v.add_decl("#include <nit_common.h>")
		var native_name = location.file.strip_extension(".nit")
		native_name += ("_nit.h")
		if native_name.file_exists then v.add_decl("#include <{native_name.basename("")}>")
		declare_class_tables_to_c(v)
		compile_mod_to_c(v)
		var f = new OFStream.open("{tc.compdir}/{name}._sep.h")
		f.write("/* This C header file is generated by NIT to compile modules and programs that requires {name}. */\n")
		f.write("#ifndef {name}_sep\n")
		f.write("#define {name}_sep\n")
		for m in mhe.direct_greaters do f.write("#include \"{m.name}._sep.h\"\n")
		for s in v.ctx.decls do
			f.write(s)
		end
		f.write("#endif\n")
		f.close

		f = new OFStream.open("{tc.compdir}/{name}._sep.c")
		f.write("/* This C file is generated by NIT to compile module {name}. */\n")
		f.write("#include \"{name}._sep.h\"\n")
		for s in v.ctx.instrs do
			f.write(s)
		end
		f.close
	end
end

