# Quel pictogramme pour quelle entrée du jeu.
# Écriture : identifiant=motif, identifiant=motif+insigne (petit motif en bas à droite), motif*n (n crans de rang).
def _lire(famille, texte):
    out = {}
    for mot in texte.split():
        k, v = mot.split('=')
        assert famille + '/' + k not in out, k
        out[famille + '/' + k] = v
    return out

TABLE = {}
TABLE.update(_lire('tech', '''
canons_masse=canon lentilles=viseur blindage_composite=bouclier_chevrons boucliers_phase=dome_bouclier boucliers_durcis=bouclier_double
interception=tourelle torpilles=torpille bastions=tour marines=casque fusiliers_elite=casque+medaille blindes_assaut=char
assaut_aeroporte=parachute plasma=faisceau essaims=missiles artillerie=artillerie chasse=chasseur canons_rail=canon_lourd
antimatiere=torpille+atome faisceaux_gamma=rayons blindage_reactif=plaques canons_singularite=trou_noir lances_stellaires=lance+soleil
verbe_final=explosion+livre_saint matiere_programmable=nano+bouclier escadres_autonomes=chasseur+puce rideau_acier=mur
frappe_profondeur=lance feu_lointain=obus equipes_prise=grappin+casque abordage=grappin guerre_usure=epees+sablier guerre_eclair=epees+eclair
genie_siege=artillerie+mur plates_formes_defense=plateforme remparts_stellaires=mur+etoile citadelle_planetaire=citadelle
doctrine_interarmes=char+chasseur infanterie_antiaerienne=missile+casque bombardement_precision=cible_planete brise_monde=planete_fissure
anneau_extinction=anneau_feu foyer_plasma_ancien=flamme+runes plans_bouclier_oublie=plan+bouclier generaux_corps=medaille
droit_guerre=balance+epees logistique_occupation=caisses+drapeau contre_mesures_crise=sirene+bouclier manuel_braves=livre_ferme+medaille

debarquement=barge propulseurs=tuyere postcombustion=tuyere+flamme detecteurs_abysse=sonde voiles_1=voile_furtif voiles_2=voile_furtif*2
voiles_3=voile_furtif*3 detecteurs_1=radar detecteurs_2=radar*2 detecteurs_3=radar*3 navigation_songe=boussole+songe ecoute_profonde=oreille
paleo_ingenierie=engrenage+runes senseurs_gravitationnels=puits_gravite capteurs=parabole telemetrie_longue=telescope
cales_rapides=cale+fleches cales_paralleles=cale*2 coques_lourdes=fregate+bouclier torpilleurs=fregate+torpille hyperflux=spirale
flux_continu=spirale+fleches coques_series=serie bombardes=vaisseau+obus baies=hangar arsenaux=cale+canon ia_bord=puce
tir_predictif=viseur+puce cuirasses=cuirasse saut_precision=saut+viseur sauts_calcules=saut coques_modulaires=coque_modules
coques_standard=serie+coche stabilisation_ver=trou_ver relais_hyperspatiaux=relais portails_saut=portail grands_portails=grand_portail
lignes_ravitaillement=chaine+caisse soutes_profondes=caisses logistique_campagne=caisse+tente ravitaillement=reservoir
navigation_stellaire=etoile_nav chantier_titanesque=grue leviathans=vaisseau nefs_mondes=nef_monde puits_gravite=puits_gravite+engrenage
etoiles_captives=etoile_cage moteur_singularite=tuyere+trou_noir ingenierie_inverse=engrenage+boucle pont_orbital=pont
inhibiteur_saut=inhibiteur architectes_stellaires=compas+etoile anneau_orbital=anneau_orbital mega_ingenierie=engrenage+planete
mega_chantier=grue+vaisseau reseau_veille=oeil+reseau centre_coordination=noeuds+etoile5 catapulte_quantique=catapulte
mega_ingenierie_avancee=engrenages+planete agglomeration=agglomerat compression_gravitationnelle=compression
moteurs_planetaires=planete+tuyere archeologie_stellaire=pioche_strates dechiffrement_strates=runes+loupe
codex_navigateurs=livre_ferme+boussole cartes_anciennes=carte+runes

reprogrammation=robot+code hydroponie=serre agronomie_orbitale=epi+orbite fusion_compacte=reacteur fusion_stabilisee=reacteur*2
extraction=pioche filons_profonds=mine academies=toque raffinage=cristal+flamme extraction_plasmine=flamme+pioche
logistique=caisses+fleches banques_donnees=banque_donnees recyclage=recycle economie_circulaire=recycle+piece bourses=courbe
automatisation=bras_robot usines_noires=usine_noire nanofabrication=nano assembleurs=molecule cristallographie=cristal+loupe
cristaux_purs=cristaux extraction_ferronoir=lingots+pioche reseaux_savants=reseau+toque arcologies_productives=arcologie+engrenage
ecopes=foreuse fabriques_autonomes=usine+robot compagnies=cargo forage_manteau=derrick cartographie_manteau=carte+pioche
extraction_etherine=fiole_nuage+pioche arcologie_planetaire=arcologie collecteur_stellaire=collecteur nexus_savoir=cerveau_etoile+livre
replicateurs=replicateur cuisine_moleculaire=molecule+epi abondance=corne post_rarete=corne+infini essaim_dyson=essaim
forge_noyau=enclume+planete siphon_geante=siphon matriochka=cerveau_etoile decompresseur=eclats+lingots
demantelement=planete_fissure+pioche fonderie_anciens=enclume+runes droit_societes=contrat courtage=echange reseau_planetaire=globe
collecte_stellaire=soleil+pile flux_galactique=galaxie+fleches

implants_neuraux=cerveau+puce resequencage=adn acclimatation_glandulaire=adn+thermo evolution_dirigee=adn+fleche_haut
matrices_conscience=matrice theorie_psionique=psi telepathie=telepathie ecrans_psychiques=ecran_psi precognition=troisieme_oeil
grammaire_etoiles=etoiles+plume oree=seuil ouverture_songe=songe adaptation=thermo administration=colonne rhetorique=megaphone
art_oratoire=bulles medecine=croix_soin sante_publique=coeur_pouls biomes_extremes=volcan chancelleries=sceau
colons_formes=groupe+toque habitats=habitat genetique=adn+flacon therapies_geniques=seringue propagande=affiche
administration2=secteurs terraformation=terraformation cadastre_algorithmique=cadastre+puce administration_quantique=colonne+atome
prefectures=palais ambassades=ambassade mondes_jardins=planete+fleur assemblee=senat spatioports=astroport
adaptation_totale=personne+globe symbiose=communion+feuille conscription_planetaire=formulaire+casque service_universel=foule+casque
medecine_campagne=croix_soin+tente propagande_front=megaphone+casque arts_holographiques=hologramme reseau_mondes=reseau+planete
conversion_culturelle=masques+echange forum_interstellaire=table_ronde oeuvre_monumentale=obelisque
recycleurs_atmospheriques=nuage+recycle ingenierie_climatique=nuage_pluie mondes_coquilles=coquille+planete
mondes_sur_mesure=planete+compas pharmacopee_perdue=flacon+runes archives_cadastrales=archives cryptographie=cadenas
contre_espionnage=masque_espion+bouclier agents_dormants=masque_espion+zzz theologie_comparee=livre_saint+balance grands_temples=temple
schisme_reforme=schisme doctrine_commandement=chevrons legendes_vivantes=statue+etoile5 protocole_cour=trone genealogies=arbre_genea
grands_mariages=anneaux sondages=graphique+personne institutions=colonne+loi droit_federal=maillet clienteles=poignee+piece
diplomatie_multilaterale=poignee xenologie=tentacules+loupe patrouilles_stellaires=fregate+oeil amnistie=chaine_brisee
xenozoologie=patte+loupe dressage=lasso biologie_leviathans=bete protectorats=bouclier+drapeau elevation=patte+fleche_haut
biosemiotique=feuille+bulles symbioses_planetaires=planete+racines douanes_stellaires=frontiere cartographie_juridique=carte+maillet
voie_songe=songe+groupe voie_televersement=televersement voie_apotheose=ascension voie_mue=papillon voie_depart=arche
restauration_ecologique=arbre+recycle

litanies=viseur+livre_saint charge_sacree=epee_cercle zelotes=casque+flamme duellistes=epees ban_vassaux=etendard
dernier_moment=sablier+epee griffes=griffes acide=gouttes esprits_lies=vaisseau+psi forges_nefs=enclume+vaisseau
cartes_lignees=carte+arbre_genea ecoles_navigateurs=boussole+toque equipages_mixtes=groupe+vaisseau spores_rapides=cocon+fleches
scriptorium=plume forges_psalmodiques=enclume+note serviteurs=mains universites=toque+colonne ganglions=cerveau digestion_totale=ver
monopole=cristal+contrat catechisme=livre_saint offrande_consacree=offrande pelerinages=route_etoile vassalite=main+couronne
tournois=lance+couronne assemblees=senat+groupe xenodiplomatie=poignee+tentacules couvees=oeufs metabolisme=coeur+recycle
geophagie=montagne+dent cristallisation=cristaux+bouclier strates_vivantes=cristal+coeur condensateurs_ame=pile+esprit
resonance_stellaire=soleil+ondes corps_denses=poing chaines_flux=chaine+eclair chassis_specialises=tete_robot+engrenage
chassis_etanches=tete_robot+goutte cocons_guerre=cocon+epee ganglion_mere=cerveau+couronne grandes_serres=serre*2
racines_profondes=racines dissemination=spores comptabilite_occulte=livre_ferme+masque_espion grandes_fetes=spectacle+foule
normalisation=formulaire+coche abris_profonds=abri signes_presages=oeil_rayons seuils=seuil+loupe longue_patience=sablier
discretion=silence rendement=courbe+engrenage inventaire=archives+coche essaimage=ruche routes_saphene=route
traducteurs_universels=bulles+globe maillage=noeuds noeuds_relais=relais+noeuds campements_fortifies=tente+mur
planques=porte+masque_espion contrats_chaine=contrat+chaine faux_papiers=passeport voile_profond=voile_furtif+vagues
chorale=note+vagues pillage_methodique=coffre+epee brouillage_piste=empreinte+croix_x nefs_elargies=nef_monde+plus
decors_holographiques=theatre+hologramme chapiteau_deux=chapiteau*2 haute_voltige=chasseur+boucle lunes_sentinelles_ii=lunes*2
croute_blindee=planete+plaques coeur_fusion=planete+flamme lignees_robustes=arbre_genea+bouclier paturages_profonds=bete+epi
chant_migration=oiseau+note audit_prealable=loupe+contrat rachat_levier=mallette+fleche_haut
formulaires_dematerialises=formulaire+puce huissiers_assermentes=tampon+maillet protocoles_viraux=virus corps_empruntes_ii=masque*2
reverie_profonde=zzz flotte_songe_durable=fregate+songe ossuaires_ii=crane*2 vitrines_climatisees=vitrine+flocon
visites_guidees=musee+groupe optique_voilee=jumelles elevation_douce=enfant+fleche_haut sable_fin=dunes
bulles_rapprochees=cerveau_etoile+fleches oeuvres_hatees=pinceau+fleches hibernation_profonde=lit cometes_semences_ii=comete*2
cometes_semences_iii=comete*3 spores_ralentissantes=spores+sablier saisons_accelerees=soleil+flocon jardinage_patient=pousse+sablier
psaumes_coursives=note+livre_saint flotte_ville_ii=ville+canon flotte_ville_iii=ville+grue serres_coursives=serre+vaisseau
ateliers_coursives=marteau_forge+vaisseau observatoire_proue=observatoire bulle_repli=cerveau_etoile+bouclier
bulle_pli=cerveau_etoile+piece oeuvre_souffle=nuage+pinceau oeuvre_orbites=orbite+pinceau oeuvre_etoile=soleil+pinceau
bordees_reglees=canon_lourd+horloge mues_coques=fregate+recycle accord_parfait=diapason corps_memoire=personne+banque_donnees

lignees_croisees_etape1=sang+poignee lignees_croisees_etape2=arbre_genea+couronne lignees_croisees=anneaux+couronne
dernier_couplet_etape1=note dernier_couplet_etape2=note*2 dernier_couplet=lyre+etoile5
charte_etape1=parchemin+plume charte_etape2=parchemin+echange charte=parchemin+sceau
terre_promise_etape1=carte+note terre_promise_etape2=route+cerveau terre_promise=route+note
legende_etape1=conteur legende_etape2=archives+medaille legende=livres+etoile5
silence_parfait_etape1=silence*1 silence_parfait_etape2=silence*2 silence_parfait=echo+croix_x
noosphere_etape1=cerveau+noeuds noosphere_etape2=cerveau+groupe noosphere=cerveau+galaxie
allumage_etape1=agglomerat+compression allumage_etape2=planete+eclair allumage=soleil+fleche_haut
opa_galactique_etape1=pieces+contrat opa_galactique_etape2=poignee+contrat opa_galactique=mallette+galaxie
administration_totale_etape1=livres+tampon administration_totale_etape2=guichet administration_totale=tampon+galaxie
saturation_etape1=ondes saturation_etape2=echo saturation=megaphone+galaxie
reve_commun_etape1=lit+groupe reve_commun_etape2=songe+oeil reve_commun=songe+galaxie
grand_rassemblement_etape1=tombes+plume grand_rassemblement_etape2=route+crane grand_rassemblement=foule+crane
musee_vivant_etape1=archives+musee musee_vivant_etape2=porte+musee musee_vivant=musee+etoile5
envol_etape1=sablier+etoile envol_etape2=phare envol=ailes
paradoxe_stable_etape1=fissure paradoxe_stable_etape2=boucle paradoxe_stable=infini
remodelage_etape1=plan+montagne remodelage_etape2=montagne+engrenage remodelage=planete+marteau_forge
biosphere_unique_etape1=champignon biosphere_unique_etape2=spores+planete biosphere_unique=planete+champignon
grand_jardin_etape1=pousse+etoiles grand_jardin_etape2=racines+echange grand_jardin=fleur+galaxie
grande_moisson_etape1=adn+coffre grande_moisson_etape2=dent+groupe grande_moisson=epi+galaxie
idole_etape1=affiche+etoile5 idole_etape2=ticket idole=etoile5+foule
'''))
TABLE.update(_lire('batiment', '''
capitale=palais+couronne ferme_hydroponique=serre centrale_fusion=reacteur complexe_minier=mine forum=bulles comptoir=comptoir
raffinerie=cristal+flamme habitats=habitat vivarium=reserve+patte station_etude=flacon observatoire=observatoire reseau_ecoute=antenne
college_sensitifs=psi+toque phare_songe=phare+songe oreille_bordure=oreille heraut=megaphone+etoile relais_passage=relais+seuil
ecran_psychique=ecran_psi bastion=tour citadelle=citadelle forteresse_orbitale=citadelle+orbite rempart_stellaire=mur
module_batterie=canon_lourd module_missiles=missiles module_blindage=plaques module_rayons=rayons module_hangar=hangar
module_antimissile=tourelle module_bouclier=dome_bouclier module_reparation=grue+croix_soin module_commandement=chevrons
module_senseurs=radar module_ecoute=oreille+losange module_mouilleur=mine_spatiale module_inhibiteur=inhibiteur
plateforme_canon=plateforme plateforme_missiles=plateforme+missile plateforme_rayons=plateforme+rayons
plateforme_antimissile=plateforme+viseur canon_ionique=faisceau+eclair batterie_planetaire=artillerie hangar_planetaire=hangar+planete
bouclier_planetaire=dome bouclier_planetaire_2=dome*2 depot_flotte=caisses+ancre spatioport=astroport grand_port=ancre
balise_fret=relais+caisse arsenal=cale+canon chantier_titanesque=grue academie=toque scriptorium=plume universite=toque+colonne
ganglion=cerveau temple=temple mausolee=mausolee cathedrale=cathedrale ferme_verticale=epi+ville centrale_confinement=atome
mine_profonde=pioche tribunal=balance prefecture=palais terraformeur=terraformation reserve_naturelle=reserve
ingenierie_climatique=nuage_pluie monde_jardin=fleur ecumenopole=ville banque_centrale=banque musee_galactique=musee
villegiature=palmier relais_hyper=relais portail_saut=portail grand_portail=grand_portail portail_ancien=arche_porte+runes
ancre_ver=trou_ver+ancre institut_armement=colonne+epees institut_genie=colonne+engrenage institut_economie=colonne+piece
institut_societe=colonne+groupe grand_scriptorium=plume*2 athenee=livres ganglion_majeur=cerveau*2 clinique=croix_soin
centre_clonage=personne+adn dome_biospherique=dome+feuille dome_renforce=dome+bouclier poste_securite=sirene
bureau_securite=oeil+cadenas maison_spectacles=masques grand_theatre=theatre bureau_renseignement=masque_espion
institut_heros=statue+etoile5 camp_recrutement=tente+casque academie_militaire=toque+epees grand_temple=temple*2
sanctuaire=sanctuaire grand_mausolee=mausolee*2 senat_local=senat bourse_commerce=courbe raffinerie_avancee=cristaux+flamme
cour_justice=maillet carriere_nourriciere=montagne+dent batteries_communes=pile serre_lumiere=serre+soleil puits_echo=puits+echo
cale_seche=cale chaine_navale=serie recycleur_orbital=recycle usine_automatisee=bras_robot atelier_nanofabrication=nano
fabrique_autonome=usine+robot replicateur=replicateur grenier_universel=silo cite_scellee=ville+cadenas
jardin_symbiotique=communion+feuille enrichissement_sols=pousse+plus forage_geothermique=derrick+flamme puits_manteau=derrick
abris_civils=abri puits_extraction=foreuse quartiers_accueil=maisons reserve_integrale=reserve+cadenas carriere_profonde=pioche_strates
condensateur_ame=pile+esprit grande_serre=serre*2 donjon_lignee=donjon reliquaire_forge=enclume+calice tribune=senat+megaphone
bassin_ponte=bassin fonderie_chassis=enclume+tete_robot campement_clan=tente tripot_portuaire=de guichet_central=guichet
siege_compagnie=mallette
'''))
TABLE.update(_lire('haut_fait', '''
budget_equilibre=balance banqueroute=coffre+croix_x premiere_compagnie=contrat multinationale=mallette+globe destination_reve=palmier
naufrageurs=cargo+crane mains_propres=main_propre cartographe=carte bout_du_monde=boussole tous_les_visages=groupe+globe
reveil_legendes=statue+soleil pionnier_mondes=planete+drapeau mere_des_peuples=foule aube_2=soleil*2 aube_3=soleil*3 aube_4=soleil*4
aube_5=soleil*5 batisseur=obelisque comptoirs_partout=comptoir chute_capitale=couronne_brisee inviolee=citadelle+bouclier
espece_parfaite=adn+etoile5 mille_visages=masque premier_elu=aureole phare_allume=phare pacte_rompu=poignee+croix_x premier_oree=seuil
grande_curee=bete+epees revenu_au_dela=porte+esprit dernier_de_chair=coeur+tete_robot premier_voile=voile_furtif spectre=masque_espion
nul_ne_passe=frontiere maitre_portes=portail premier_leviathan=vaisseau premiere_nef=nef_monde tueur_de_geant=geant+epee
premiere_loi=loi fondateur_koinon=table_ronde grande_paix=rameau revelation=oeil_rayons voix_qui_porte=megaphone
coup_du_siecle=dague+piece tueur_de_gardien=trophee_tete bouclier_galaxie=bouclier+galaxie sommeil_rendu=zzz
chercheur_curiosites=loupe semeur_mondes=graine+planete createur_richesse=pieces vainqueur_escarmouches=epees
archeologue=pioche_strates batisseur_empire=ville promoteur_sciences=atome conglomerats=mallette conquerant_systemes=systeme+drapeau
faiseur_traites=parchemin+sceau lieux_saints=temple+bouclier maitre_espion=dague chasseur_pirates=pavillon_pirate+viseur
explorateur_abimes=sonde consolidateur=secteurs collectionneur_eurekas=ampoule monopoliste=gemme maitre_sieges=artillerie+mur
suzerain=couronne+groupe conservateur=vitrine toile_araignee=toile dompteur=lasso coeur_battant=coeur_pouls
esprit_encyclopedique=livres corne_abondance=corne levee_en_masse=foule+casque legislateur=maillet
conversion_capitale=temple+couronne multitudes=ruche bout_arbre=arbre+etoile5 banquier_etoiles=banque invaincu=laurier
casse_millenaire=coffre+masque_espion empire_marchand=cargo grande_digestion=ver cathedrale_cathedrales=cathedrale idole=spectacle
serment_tenu=epee+main derniers_debout=etendard briseur_mondes=planete_fissure fossoyeur_traites=parchemin+croix_x
bruleur_archives=livres+flamme survivant=feu_camp tresor_quetes=coffre phenix=phenix david=fronde long_silence=silence
kardashev_ii=sphere_dyson kardashev_iii=galaxie premier_monde_anneau=anneau_orbital pas_seuls=parabole ce_que_nous_fumes=miroir
ne_pas_repondre=antenne+crane atelier_de_mondes=planete+marteau_forge le_grand_vide=trou_noir premier_berceau=planete+boucle
trois_reconstitutions=jarre+eclats musee_theme=musee cercle_decimales=pi prise_titan=cuirasse+grappin flotte_prises=serie+grappin
ferrailleur=epave+engrenage jardinier_kynes=dunes+pousse terre_brulee=cendres au_bord_abime=vortex
'''))
TABLE.update(_lire('relique', '''
couronne_aube=couronne_rayons lame_veuve=epee graal_vide=calice astrolabe_premier=astrolabe codex_ombres=livre_ferme+lune
coeur_etoile=bocal enclume_monde=enclume codex_origines=livre semence_eden=graine sceau_concorde=sceau bouclier_martyr=bouclier_croix
masque_mille=masque horloge_fin=sablier os_titan=os larme_vide=larme cloche_rappel=cloche carte_infinie=carte+infini
trone_poussiere=trone lanterne_morts=lanterne harpe_spheres=harpe graine_noire=graine+lune oeil_cyclope=oeil ancre_monde=ancre
plume_scribe=plume relique_inconnue=point_interro croc_vouivre=dent coeur_veilleur=coeur+oeil cle_citadelle=cle
voile_matriarche=voile_tissu dent_mange_soleil=dent+soleil reine_nid=couronne+ruche coquille_oeuf=oeuf_fissure
tete_ferrailleur=tete_robot oeil_portes=portail+oeil flamme_spectre=flamme corne_migration=cor epee_serment=epee_cercle
voile_aube=voile_tissu+soleil theoreme_ultime=triangle_th grand_livre=livre_ferme+piece coeur_couvee=oeufs+coeur
coeur_passage=eclat+seuil cle_tombeaux=cle+crane chant_fige=cristal+note tampon_supreme=tampon eclat_faille=eclat
eclat_avorte=eclats dent_outre_nuit=dent+lune plan_hote=plan quittance_songe=contrat+songe lueur_phare=phare premier_sou=piece
couronne_corsaire=couronne+pavillon_pirate cloche_ylm=vitrine+cloche sceau_kheb=sceau+runes cierge_aube=cierge index_aster=doigt
clochette_orrhe=clochette navette_hel=navette etendard_cendre=etendard graine_ouvre=pousse balance_ports=balance
diapason_silence=diapason
'''))
TABLE.update(_lire('precepte', '''
liturgie=note pelerinage=route_etoile reliquaires=sarcophage aniconisme=statue+croix_x astrologie=etoiles sacrifices=autel
resonance=diapason ascetisme=bol charite=offrande pacifisme=rameau loi_sacree=tablette preservation=arbre+bouclier
doute_sacre=point_interro dime=pieces ethique_travail=marteau_forge croissez=enfant saintete_chair=aureole chair_argile=adn
propriete_eglise=temple+cle moines_guerriers=epee_cercle sanctuaire=sanctuaire pelerins_armes=pelerin+epee xenolatrie=tentacules
gardiens_monde=globe+bouclier sacralite_vivant=feuille
'''))
TABLE.update(_lire('nature', '''
code_saint=code meme=megaphone+virus parasite=parasite precurseurs=runes voies_sacrees=arche_porte eglise_universelle=cathedrale
patriarcats=trone loi_extase=livre_saint karma=roue harmonie=yinyang pantheon=pantheon ancetres=ancetres dette_sang=sang
dieu_present=oeil_triangle chronolatrie=horloge dieu_en_chantier=chantier_dieu entropisme=entropie communion=communion
astres_vivants=soleil culte_partis=porte grand_spectacle=spectacle traversee=barque
'''))
TABLE.update(_lire('fouille', '''
necropole=tombes cite=cite_engloutie observatoire=observatoire champ=epees arche=arche sanctuaire=sanctuaire epave=epave
tisserands=navette cendree=etendard jardiniers=pousse ports=ancre chanteurs=diapason savoir=livre art=lyre arme=epee
prudente=pinceau methodique=loupe pillage=pioche
'''))
TABLE.update(_lire('ressource', '''
soie_vide=toile epices_kesh=epices vin_nebuleuse=verre ambre_chantant=ambre perles_glace=collier encens_fossile=encensoir
bois_coeur=buche corail_orage=corail larmes_quasar=larme plumes_phenix=plume_feu cristal_memoire=cristal lait_etoile=bouteille
plasmine=flamme ferronoir=lingots etherine=fiole_nuage
'''))
