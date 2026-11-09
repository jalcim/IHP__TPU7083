/* Groupes d'une passe, source unique de G_S1, G_MAX et G_LOW (variante G1 de
 * rtl/contrats.md) : une passe au pas 1 a G_S1 groupes, G1 quand il
 * n'est pas nul et G sinon, une passe au pas 2 en a G, G_MAX est le plus grand des deux et G_LOW le plus petit.
 * Chaque module qui en a besoin inclut ce fichier dans son corps et appelle ces fonctions constantes dans la liste de
 * ses paramètres, si bien qu'une formule retouchée suit partout les paramètres que la tuile passe.
 * Les fonctions appartiennent au module qui les inclut : le fichier n'a donc pas de garde d'inclusion, qui empêcherait
 * la seconde inclusion dans un autre module. */

function integer groups_stride1(input integer groups, input integer groups1);
    groups_stride1 = (groups1 != 0) ? groups1 : groups;
endfunction

function integer groups_max(input integer groups, input integer groups1);
    groups_max = (groups_stride1(groups, groups1) > groups) ? groups_stride1(groups, groups1) : groups;
endfunction

function integer groups_low(input integer groups, input integer groups1);
    groups_low = (groups_stride1(groups, groups1) < groups) ? groups_stride1(groups, groups1) : groups;
endfunction
