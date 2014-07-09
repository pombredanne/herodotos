
let match_bug strict prefix bug1 bug2 =
  let (_, s, _, f, v, pos, _, t, h, _, _) = bug1 in
  let (_, sb, _, fb, vb, posb, _, tb, hb, _, _) = bug2 in
    f = fb && v = vb && pos = posb
(*       && h.Ast_org.is_head = true *)
(*       && hb.Ast_org.is_head = true *)
      && (if strict then
	    let new_t = Org.clean_link_text prefix v f pos t in
	    let new_tb = Org.clean_link_text prefix v f pos tb in
	      if !Misc.debug then
		begin
		  prerr_string ("MATCH_BUG: \""^ new_t^ "\"");
		  prerr_endline (" <-> \""^ new_tb^ "\"");
		  prerr_endline "Auto-correlation OK\n=========";
		end;
	      new_t = new_tb
	  else true)

let rec get_chain (bug:Ast_org.bug) =
  let (l, s, r, f, v, pos, face, t, h, n, sub) = bug in
    match n.Ast_org.def with
	None -> [bug]
      | Some (None) -> [bug]
      | Some (Some nbug) -> bug::get_chain nbug

let is_head bug =
  let (l, s, r, f, v, pos, face, t, h, n, sub) = bug in
    h.Ast_org.is_head

let extract_chain ext_file (bugs: Ast_org.orgarray) : Ast_org.bugs list =
  let heads =
    Array.fold_left
      (fun head (flist, tbl) ->
	 List.fold_left
	   (fun fhead file ->
	      if ext_file = file then
		List.fold_left
		  (fun bhead bug ->
		     if is_head bug then
		       (get_chain bug)::bhead
		     else
		       bhead
		  ) fhead (Hashtbl.find tbl file)
	      else
		fhead
	   ) head flist
      ) [] bugs
  in
    heads

let get_bug strict prefix (bug: Ast_org.bug) (bugs: Ast_org.bug list) : Ast_org.bug =
  List.find (match_bug strict prefix bug) bugs

let get_next_list vlist bugs f vidx =
  let (_, tbl) = Array.get bugs (vidx+1) in
    try
      Hashtbl.find tbl f
    with Not_found -> []

let update_nohead bug =
  let (l, s, r, f, v, p, face, t, h, n, subs) = bug in
  h.Ast_org.is_head <- false

let manual_check_next verbose strict prefix correl subbugs bug =
  let (l, s, r, f, v, p, face, t, h, n, _) = bug in
  let t = if strict then (Org.clean_link_text prefix v f p t) else "" in
  if verbose then prerr_endline ("Trying manual correlation of "^f^" ver. "^v);
  try
    let correlb = List.find (fun b ->
      let (st, file, ver, pos, _, _, _, ctext) = b in
      st = Ast_org.SAME
      && f = file
	&& v = ver
	  && p = pos
	    && (if strict
	      then
		let new_t = Org.clean_link_text prefix v f pos ctext in
		if !Misc.debug then
		  begin
		    prerr_string ("\""^ new_t^ "\"");
		    prerr_endline (" <-> \""^ t^ "\"");
		    prerr_endline "Auto-correlation OK\n=========";
		  end;
		new_t = t
	      else true
	    )
    ) correl in
    let (_, _, _, _, nfile, nver, next_pos, _) = correlb in
    let check = (l, s, r, nfile, nver, next_pos, "", t, {Ast_org.is_head=true}, {Ast_org.def=None}, []) in
    (try
       let next = get_bug strict prefix check subbugs in
       n.Ast_org.def <- Some (Some next);
       update_nohead next;
       if verbose then prerr_endline "Manual correlation OK\n=========";
       0 (* No automatic correlation performed *)
     with Not_found ->
       if verbose then prerr_endline "Manual correlation KO\n=========";
       0 (* No automatic correlation performed *)
    )
  with Not_found ->
    if verbose then prerr_endline "Manual correlation KO - KO\n=========";
    0 (* No automatic correlation performed *)

let rec check_alt_next verbose strict prefix depth vlist diffs correl bugs bug : int =
  let (l, s, r, f, v, p, face, t, h, n, _) = bug in
  let vidx = Misc.get_idx_of_version vlist v in
  let subbugs = get_next_list vlist bugs f vidx in
  match Diff.alt_new_pos diffs f v p with
      None -> manual_check_next verbose strict prefix correl subbugs bug
    | Some (_, diffcheck_pos) ->
      match diffcheck_pos with
	  (Ast_diff.Sing line,colb,cole) ->
	    ignore(check_next verbose strict true prefix depth vlist diffs correl bugs bug (line,colb,cole));
	    if n.Ast_org.def = Some (None) then
	      manual_check_next verbose strict prefix correl subbugs bug
	    else
	      1 (* Automatic correlation performed *)
	| (Ast_diff.Deleted _, colb,cole) ->
	  n.Ast_org.def <- Some (None);
	  1 (* Considered as an automatic correlation *)
	| (Ast_diff.Unlink, _, _) -> (* File has been removed. *)
	  if !Misc.debug then prerr_endline "Auto-correlation OK\n=========";
	  n.Ast_org.def <- Some (None);
	  1 (* Considered as an automatic correlation *)
	| (Ast_diff.Cpl (lineb,linee),colb, cole) ->
	  let rec fold line =
	    let (res, _) = check_next verbose strict true prefix depth vlist diffs correl bugs bug (line,colb,cole) in
	    if res = 0 then        (* Nothing at line 'line' *)
	      if line < linee then (* Check next lines until 'linee' *)
		fold (line+1)
	      else 0
	    else 1                 (* Found something. Stop there. *)
	  in ignore(fold lineb);   (* Start looking for next bug at line 'lineb' *)
	  if n.Ast_org.def = Some (None) then
	    manual_check_next verbose strict prefix correl subbugs bug
	  else
	    1 (* Automatic correlation performed *)

and check_next verbose strict conf prefix depth vlist diffs correl (bugs:Ast_org.orgarray) (bug:Ast_org.bug) check_pos
    : int * (string * ((Ast_org.bug -> int) * Ast_org.bug)) list =
  Debug.profile_code_silent "check_next"
    (fun () ->
      let (l, s, r, f, v, p, face, t, h, n, _) = bug in
      let t = if strict then (Org.clean_link_text prefix v f p t) else "" in
      let vidx = Misc.get_idx_of_version vlist v in
      let subbugs = get_next_list vlist bugs f vidx in
      let vn = Misc.get_version_name vlist (vidx+1) in
      let check = (l, s, r, f, vn, check_pos, face, t, {Ast_org.is_head=true}, {Ast_org.def=None}, []) in
      if verbose then
	(
	  prerr_string "check_next of ";
	  Org.show_bug true bug;
	  prerr_string (" at ");
	  Org.show_bug true check;
	  prerr_newline ();
	  prerr_endline ("List:");
	  List.iter (Org.show_bug true) subbugs;
	  prerr_newline ();
	);
      try
	let next = get_bug strict prefix check subbugs in
	if (n.Ast_org.def = None) then
	  begin
	    n.Ast_org.def <- Some (Some next);
	    update_nohead next;
	    (1, []) (* One automatic correlation performed *)
	  end
	else
	  failwith "Already defined next !" (* No automatic correlation performed *)
      with Not_found ->
	if conf then
	  begin
	    if verbose then prerr_endline "Automatic correlation OK\n=========";
	    n.Ast_org.def <- Some (None);
	    (1, []) (* Automatic correlation performed *)
	  end
	else
	  (0, [(Hybrid.get_cmd2 f v, (check_alt_next verbose strict prefix depth vlist diffs correl bugs, bug))])
    )

let compute_bug_next verbose strict prefix depth vlist diffs correl bugs bug =
  Debug.profile_code_silent "compute_bug_next"
    (fun () ->
       let (l, s, r, f, v, p, face, t, h, n, _) = bug in
	 if verbose then
	   (
	     Org.show_bug true bug;
	     prerr_newline ()
	   );
	 let (conf, diffcheck_pos) = Diff.compute_new_pos diffs f v p in
	   if verbose then
	     (prerr_string (Org.get_string_pos p);
	      prerr_string " as new pos: ";
	      match diffcheck_pos with
		  (Ast_diff.Sing line,colb,cole) ->
		    let check_pos = (line, colb, cole) in
		      prerr_endline (Org.get_string_pos check_pos)
		| (Ast_diff.Deleted _, _,_) ->
		    prerr_endline "Deleted line"
		| (Ast_diff.Unlink, _,_) ->
		    prerr_endline "Deleted file"
		| (Ast_diff.Cpl (lineb,linee),colb, cole) ->
		    prerr_endline "Somewhere"
	     );
	   match diffcheck_pos with
	       (Ast_diff.Sing line,colb,cole) -> (* We are between two hunks. *)
		 check_next verbose strict conf prefix depth vlist diffs correl bugs bug (line,colb,cole)
	     | (Ast_diff.Deleted cont, colb, cole) ->
	       if not conf then
	       (*
		 We are inside a hunk and lines have been removed.
		 Check for manual correlation.
	       *)
		 check_next verbose strict conf prefix depth vlist diffs correl bugs bug (0,colb,cole)
	       else
		 if cont then
		   (* Considered as uncorrelated. Continuation will check with the alternative algorithm. *)
		   (0, [(Hybrid.get_cmd2 f v, (check_alt_next verbose strict prefix depth vlist diffs correl bugs, bug))])
		 else
		   begin
		     n.Ast_org.def <- Some (None);
		     (1, []) (* Considered as an automatic correlation *)
		   end
	     | (Ast_diff.Unlink, _, _) ->
	         (*
		   File has been removed.
		 *)
	       if !Misc.debug then prerr_endline "Auto-correlation OK\n=========";
	       n.Ast_org.def <- Some (None);
	       (1, []) (* Considered as an automatic correlation *)
	     | (Ast_diff.Cpl (lineb,linee),colb, cole) -> (* We are inside a hunk. *)
		 (*
		   Could we do something for bugs inside a hunk ?
		   It seems to be impossible and worthless.
		   Just check for manual correlation.
		 *)
	       let rec fold line =
		 let (res, _) = check_next verbose strict conf prefix depth vlist diffs correl bugs bug (line,colb,cole) in
		 if res = 0 then
		   if line < linee then
		     fold (line+1)
		   else 0
		 else 1
	       in (fold lineb, [])
    )

(*
Parmap.parmap ~ncores:nc' ~chunksize: cs' pixel (Parmap.L tasks)
*)

let compute_bug_chain verbose strict prefix depth count vlist diffs correl bugs =
  Debug.profile_code_silent "compute_bug_chain"
    (fun () ->
      Array.fold_left
	(fun acc (flist, tbl) ->
	  begin
	    List.fold_left
	      (fun acc file ->
		let subbugs = Hashtbl.find tbl file in
(**)
		List.fold_left
		  (fun (res_acc, ks_acc) bug ->
		    let (res, ks) = compute_bug_next verbose strict prefix depth vlist diffs correl bugs bug in
		    (res_acc + res, ks_acc @ ks)
		  ) acc subbugs
(**)
	      ) acc flist
	  end
	) (0, []) bugs
    )

let find_all_org_in org orgs =
  let (_, so, _, fo, vo, po, _, to_, _, _, _) = org in
    List.find_all (fun (_, s, _, f, v, p, _, t, _, _, _) ->
		     f = fo && v = vo && p = po
		  ) orgs

let update_status vlist annots (bugs:Ast_org.bugs) : int * Ast_org.bugs =
  Debug.profile_code_silent "update_status"
    (fun () ->
       let (stats, res) =
	 List.split
	   (List.map
	      (fun bug ->
		 let (l, s, r, f, v, pos, face, t, h, n, sub) = bug in
		 let (new_bug, new_s, new_r, new_t) =
		   let idx = Misc.get_idx_of_version vlist v in
		   let (_,tbl) = Array.get annots idx in
		     try
		       match find_all_org_in bug (Hashtbl.find tbl f) with
			   [] -> (true, s, r, t)
			 | [new_] ->
			     let (_, new_s, new_r, _, _, _, _, new_t, _, _, _) = new_ in
			       (false, new_s, new_r, new_t)
			 | matching -> (false, s, r, t)
		     with Not_found ->
		       (true, s, r, t)
		 in
		   (new_bug, (l, new_s, new_r, f, v, pos, face, new_t, h, n, sub))
	      ) bugs
	   )
       in
	 (List.length (List.filter (fun x -> x) stats), res)
    )

let unique_file_list orgarray =
  Debug.profile_code_silent "unique_file_list"
    (fun () ->
       let file_list = Array.fold_left (fun head (flist, _) -> head @ flist) [] orgarray in
	 Misc.unique_list file_list
    )

let run_pariter f cmd : int =
  let pid = Unix.fork () in
    if pid = 0 then (* I'm a slave *)
      begin
	let pid = Unix.getpid() in
	if !Misc.debug then prerr_endline ("New child "^ string_of_int pid^ " for "^cmd);
	let status = f cmd in
	if !Misc.debug then prerr_endline ("Job done for child "^ string_of_int pid);
	let msg = Debug.profile_diagnostic () in
	if msg <> "" then prerr_endline msg;
	exit status
      end
    else (* I'm the master *)
      pid

let dispatch_pariter cpucore f (perr, pidlist) cmd : int * int list =
  let (error, newlist) =
    if List.length pidlist > cpucore then
      let (death, status) = Unix.wait () in
      if !Misc.debug then
	prerr_endline ("Master: Job done for child "^ string_of_int death);
      let error = match status with
	  Unix.WEXITED 0 -> perr
	| _              -> perr + 1
      in
      (error, List.filter (fun x -> x <> death) pidlist)
    else
      (perr, pidlist)
  in
  let pid = run_pariter f cmd in
  (error, pid::newlist)

let pariter cpucore f cmds : unit =
  Debug.profile_code_silent "pariter"
    (fun () ->
      let error =
	if cpucore = 1 then
	  (List.iter (fun x -> ignore (f x)) cmds;  0)
	else
	  let (err, pidlist) =
	    List.fold_left
	      (dispatch_pariter cpucore f)
	      (0, [])
	      cmds
	  in
	  let res = List.map (fun x ->
	    let (death, status) = Unix.wait () in
	    if !Misc.debug then
	      prerr_endline ("Master: Job done for child "^ string_of_int death);
	    match status with
		Unix.WEXITED 0 -> 0
	      | _ -> 1
	  ) pidlist
	  in
	  List.fold_left (+) err res
      in
      if error <> 0 then
	prerr_endline ("*** ERROR *** "^string_of_int error ^" error(s) during the cache update.")
    )

let compute_org verbose cpucore strict prefix depth vlist diffs correl (annots:Ast_org.orgarray) (orgs:Ast_org.orgarray) :
    (int * int) * ((Ast_diff.path * Ast_org.bugs list) list) =
  Debug.profile_code_silent "compute_org"
    (fun () ->
      if verbose then prerr_endline ("*** CORRELATION - PHASE 1 ***");
       let (initial_count, ks) = compute_bug_chain verbose strict prefix depth 0 vlist diffs correl orgs in
       (* Update gumtree cache with missing files *)
       let re = Str.regexp_string "&&" in
       let (cmds, ks2) = List.split ks in
       let (dirs, cleaned_cmds) =
	 List.fold_left
	   (fun (dir_list, cmd_list) x ->
	     if x <> "" then
	       let (dir, cmd) = match Str.split re x with
		   dir::[cmd] -> (dir, cmd)
		 | _ -> failwith ("Wrong command: x")
	       in
	       let dirs = if not (List.mem dir dir_list) then
		   dir::dir_list else dir_list
	       in
	       let cmds = if not (List.mem cmd cmd_list) then
		   cmd::cmd_list else cmd_list
	       in (dirs, cmds)
	     else
	       (dir_list, cmd_list)
	   )
	   ([],[]) cmds
       in
       if verbose then prerr_endline ("*** UPDATING GUMTREE CACHE *** "^ string_of_int (List.length cleaned_cmds) ^" item(s).");
       List.iter (fun cmd ->
	   match
	     Unix.system cmd
	   with
	       Unix.WEXITED 0 -> ()
	     | Unix.WEXITED 1 -> ()
	     | Unix.WEXITED i -> prerr_endline ("*** FAILURE *** Code:" ^(string_of_int i) ^" "^ cmd)
	     | _ -> prerr_endline ("*** FAILURE *** " ^cmd)
       ) dirs;
       pariter cpucore (fun cmd ->
	 if verbose then prerr_endline ("Run "^cmd);
	 let status =
	   match
	     Unix.system cmd
	   with
	       Unix.WEXITED 0 -> true
	     | Unix.WEXITED 1 -> false
	     | Unix.WEXITED i -> prerr_endline ("*** FAILURE *** Code:" ^(string_of_int i) ^" "^ cmd); false
	     | _ -> prerr_endline ("*** FAILURE *** " ^cmd); false
	 in
	 if status then
	   Unix.execv "/bin/true" (Array.of_list [])
	 else
	   Unix.execv "/bin/false" (Array.of_list [])
       ) cleaned_cmds;
	(*	*)
       if verbose then prerr_endline ("*** CORRELATION - PHASE 2 *** " ^ string_of_int (List.length ks2) ^ " item(s).");
       let count =
	 List.fold_left
	   (fun acc (f, bug) ->
	     acc + f bug
	   ) initial_count ks2
       in
	(*	*)
       let (new_bugs, correlorg) =
	 List.split (
	   List.map (fun file ->
		       if !Misc.debug then prerr_endline ("COMPUTE ORG - Processing file " ^file);
			 (* 		  let sorted = sort_bugs strict prefix bugs in *)
		       let sorted = extract_chain file orgs in
		       let (stats, updbugs) = List.split (List.map (update_status vlist annots) sorted) in
 		       let new_bugs = List.fold_left (+) 0 stats in
			 (new_bugs), (file, updbugs))
	     (unique_file_list orgs)
	 )
       in
       let new_bug_count = List.fold_left (+) 0 new_bugs in
	 ((count, new_bug_count), correlorg)
    )
