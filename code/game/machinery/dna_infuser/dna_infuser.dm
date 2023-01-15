/// how long it takes to infuse
#define INFUSING_TIME 4 SECONDS
/// we throw in a scream along the way.
#define SCREAM_TIME 3 SECONDS

/obj/machinery/dna_infuser
	name = "\improper DNA infuser"
	desc = "A defunct genetics machine for merging foreign DNA with a subject's own."
	icon = 'icons/obj/machines/cloning.dmi'
	icon_state = "infuser"
	base_icon_state = "infuser"
	density = TRUE
	obj_flags = NO_BUILD // Becomes undense when the door is open
	circuit = /obj/item/circuitboard/machine/dna_infuser
	///currently infusing a vict- subject
	var/infusing = FALSE
	///what we're infusing with
	var/atom/movable/infusing_from
	///what we're turning into
	var/datum/infuser_entry/infusing_into
	///a message for relaying that the machine is locked if someone tries to leave while it's active
	COOLDOWN_DECLARE(message_cooldown)

/obj/machinery/dna_infuser/Initialize(mapload)
	. = ..()
	occupant_typecache = typecacheof(/mob/living/carbon/human)

/obj/machinery/dna_infuser/Destroy()
	. = ..()
	//dump_inventory_contents called by parent, emptying infusing_from
	infusing_into = null

/obj/machinery/dna_infuser/examine(mob/user)
	. = ..()
	if(!occupant)
		. += span_notice("Requires [span_bold("a subject")].")
	else
		. += span_notice("\"[span_bold(occupant.name)]\" is inside the infusion chamber.")
	if(!infusing_from)
		. += span_notice("Missing [span_bold("an infusion source")].")
	else
		. += span_notice("[span_bold(infusing_from.name)] is in the infusion slot.")
	. += span_notice("To operate: Obtain dead creature. Depending on size, drag or drop into the infuser slot.")
	. += span_notice("Subject enters the chamber, someone activates the machine. Voila! One of your organs has... changed!")
	. += span_notice("Alt-click to eject the infusion source, if one is inside.")

/obj/machinery/dna_infuser/interact(mob/user)
	if(user == occupant)
		toggle_open(user)
		return
	if(infusing)
		balloon_alert(user, "not while it's on!")
		return
	if(occupant && infusing_from)
		// Abort infusion if the occupant is invalid.
		if(!is_valid_occupant(occupant, user))
			playsound(src, 'sound/machines/scanbuzz.ogg', 35, vary = TRUE)
			return
		balloon_alert(user, "starting DNA infusion...")
		start_infuse()
		return
	toggle_open(user)

/obj/machinery/dna_infuser/proc/start_infuse()
	var/mob/living/carbon/human/human_occupant = occupant
	infusing = TRUE
	visible_message(span_notice("[src] hums to life, beginning the infusion process!"))
	// Replace infusing_into with a [/datum/infuser_entry]
	for(var/datum/infuser_entry/entry as anything in GLOB.infuser_entries)
		if(is_type_in_list(infusing_from, entry.input_obj_or_mob))
			infusing_into = entry
			break
	if(!infusing_into)
		//no valid recipe, so you get a fly mutation
		infusing_into = GLOB.infuser_entries[1]
	playsound(src, 'sound/machines/blender.ogg', 50, vary = TRUE)
	to_chat(human_occupant, span_danger("Little needles repeatedly prick you! And with each prick, you feel yourself becoming more... [infusing_into.infusion_desc]?"))
	human_occupant.take_overall_damage(10)
	human_occupant.add_mob_memory(/datum/memory/dna_infusion, protagonist = human_occupant, deuteragonist = infusing_from, mutantlike = infusing_into.infusion_desc)
	Shake(15, 15, INFUSING_TIME)
	addtimer(CALLBACK(human_occupant, TYPE_PROC_REF(/mob, emote), "scream"), INFUSING_TIME - 1 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(end_infuse)), INFUSING_TIME)
	update_appearance()

/obj/machinery/dna_infuser/proc/end_infuse()
	infuse_organ(occupant)
	infusing = FALSE
	infusing_into = null
	QDEL_NULL(infusing_from)
	playsound(src, 'sound/machines/microwave/microwave-end.ogg', 100, vary = FALSE)
	toggle_open()
	update_appearance()

/// Attempt to replace/add-to the occupant's organs with "mutated" equivalents.
/// Returns TRUE on success, FALSE on failure.
/// Requires the target mob to have an existing organic organ to "mutate".
// TODO: In the future, this should have more logic:
// - Replace non-mutant organs before mutant ones.
/obj/machinery/dna_infuser/proc/infuse_organ(mob/living/carbon/human/target)
	if(!ishuman(target) || !infusing_into)
		// Already filters humans from entering, but you know, just in case.
		return
	var/list/obj/item/organ/potential_new_organs = infusing_into.output_organs.Copy()
	// Filter incompatible or identical organs from being inserted.
	for(var/obj/item/organ/old_organ as anything in (target.internal_organs.Copy() + target.external_organs.Copy()))
		if(old_organ.type in potential_new_organs)
			// Occupant already has the same mutated organ.
			potential_new_organs -= old_organ.type

	// Nothing to mutate.
	if(!length(potential_new_organs))
		return FALSE

	var/obj/item/organ/new_organ
	// To validate further additions, each remaining organ must be instantiated.
	do
		new_organ = pick(potential_new_organs)
		new_organ = new new_organ()
		var/obj/item/organ/old_organ = target.getorganslot(new_organ.slot)
		if(old_organ)
			// Existing organ is organic / can be mutated.
			if(old_organ.status == ORGAN_ORGANIC)
				break
		// Occupant lacks the organ, but can grow an appendage.
		else if(istype(new_organ, /obj/item/organ/external))
			break
		// Organ is either missing or non-organic.
		potential_new_organs -= new_organ.type
		new_organ = null
		if(!length(potential_new_organs))
			return FALSE
	while(!new_organ)

	if(!istype(new_organ, /obj/item/organ/internal/brain))
		// Organ ISN'T brain, insert normally.
		new_organ.Insert(target, special = TRUE, drop_if_replaced = FALSE)
		return TRUE
	// Organ IS brain, insert via special logic:
	var/obj/item/organ/internal/brain/old_brain = target.getorganslot(ORGAN_SLOT_BRAIN)
	// Brains REALLY like ghosting people. we need special tricks to avoid that, namely removing the old brain with no_id_transfer
	old_brain.Remove(target, special = TRUE, no_id_transfer = TRUE)
	qdel(old_brain)
	var/obj/item/organ/internal/brain/new_brain = new_organ
	new_brain.Insert(target, special = TRUE, drop_if_replaced = FALSE, no_id_transfer = TRUE)
	return TRUE

/obj/machinery/dna_infuser/update_icon_state()
	//out of order
	if(machine_stat & (NOPOWER | BROKEN))
		icon_state = base_icon_state
		return ..()
	//maintenance
	if((machine_stat & MAINT) || panel_open)
		icon_state = "[base_icon_state]_panel"
		return ..()
	//actively running
	if(infusing)
		icon_state = "[base_icon_state]_on"
		return ..()
	//open or not
	icon_state = "[base_icon_state][state_open ? "_open" : null]"
	return ..()

/obj/machinery/dna_infuser/proc/toggle_open(mob/user)
	if(panel_open)
		if(user)
			balloon_alert(user, "close panel first!")
		return
	if(state_open)
		close_machine()
		return
	else if(infusing)
		if(user)
			balloon_alert(user, "not while it's on!")
		return
	open_machine(drop = FALSE)
	//we set drop to false to manually call it with an allowlist
	dump_inventory_contents(list(occupant))

/obj/machinery/dna_infuser/attackby(obj/item/used, mob/user, params)
	if(infusing)
		return
	if(!occupant && default_deconstruction_screwdriver(user, icon_state, icon_state, used))//sent icon_state is irrelevant...
		update_appearance()//..since we're updating the icon here, since the scanner can be unpowered when opened/closed
		return
	if(default_pry_open(used))
		return
	if(default_deconstruction_crowbar(used))
		return
	if(ismovable(used))
		add_infusion_item(used, user)
	return ..()

/obj/machinery/dna_infuser/relaymove(mob/living/user, direction)
	if(user.stat)
		if(COOLDOWN_FINISHED(src, message_cooldown))
			COOLDOWN_START(src, message_cooldown, 4 SECONDS)
			to_chat(user, span_warning("[src]'s door won't budge!"))
		return
	if(infusing)
		if(COOLDOWN_FINISHED(src, message_cooldown))
			COOLDOWN_START(src, message_cooldown, 4 SECONDS)
			to_chat(user, span_danger("[src]'s door won't budge while all the needles are infusing you!"))
		return
	open_machine(drop = FALSE)
	//we set drop to false to manually call it with an allowlist
	dump_inventory_contents(list(occupant))

// mostly good for dead mobs that turn into items like dead mice (smack to add).
/obj/machinery/dna_infuser/proc/add_infusion_item(obj/item/target, mob/user)
	// if the machine is closed, already has a infusion target, or the target is not valid then no adding.
	if(!state_open || !is_valid_infusion(target, user))
		return
	if(!user.transferItemToLoc(target, src))
		to_chat(user, span_warning("[target] is stuck to your hand!"))
		return
	infusing_from = target

// mostly good for dead mobs like corpses (drag to add).
/obj/machinery/dna_infuser/MouseDrop_T(atom/movable/target, mob/user)
	// if the machine is closed, already has a infusion target, or the target is not valid then no mouse drop.
	if(!state_open || !is_valid_infusion(target, user))
		return
	infusing_from = target
	infusing_from.forceMove(src)

/// Verify that the occupant/target is organic, and has mutable DNA.
/obj/machinery/dna_infuser/proc/is_valid_occupant(mob/living/carbon/human/human_target, mob/user)
	// Invalid: Occupant isn't Human, isn't organic, lacks DNA / has TRAIT_GENELESS.
	if(!ishuman(human_target) || !(human_target.mob_biotypes & MOB_ORGANIC) || !human_target.has_dna() || HAS_TRAIT(human_target, TRAIT_GENELESS))
		balloon_alert(user, "dna is missing!")
		return FALSE
	// Invalid: DNA is too damaged to mutate anymore / has TRAIT_BADDNA.
	if(HAS_TRAIT(human_target, TRAIT_BADDNA))
		balloon_alert(user, "dna is corrupted!")
		return FALSE
	// Valid: Occupant is an organic Human who has undamaged and mutable DNA.
	return TRUE

/// Verify that the given infusion source/mob is a dead creature.
/obj/machinery/dna_infuser/proc/is_valid_infusion(atom/movable/target, mob/user)
	if(user.stat != CONSCIOUS || HAS_TRAIT(user, TRAIT_UI_BLOCKED) || !Adjacent(user) || !user.Adjacent(target) || !ISADVANCEDTOOLUSER(user))
		return FALSE
	var/datum/component/edible/food_comp = IS_EDIBLE(target)
	if(infusing_from)
		balloon_alert(user, "empty the machine first!")
		return FALSE
	if(isliving(target))
		var/mob/living/living_target = target
		if(living_target.stat != DEAD)
			balloon_alert(user, "only dead creatures!")
			return FALSE
	else if(food_comp)
		if(!(food_comp.foodtypes & GORE))
			balloon_alert(user, "only creatures!")
			return FALSE
	else
		return FALSE
	return TRUE

/obj/machinery/dna_infuser/AltClick(mob/user)
	. = ..()
	if(infusing)
		balloon_alert(user, "not while it's on!")
		return
	if(!infusing_from)
		balloon_alert(user, "no sample to eject!")
		return
	balloon_alert(user, "ejected sample")
	infusing_from.forceMove(get_turf(src))
	infusing_from = null

#undef INFUSING_TIME
