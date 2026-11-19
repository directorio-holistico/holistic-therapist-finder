// Names of people are stored with a capital letter only at the start of each name: "LILIANA GARCIA SERRANO" or "liliana garcia
// serrano" -> "Liliana Garcia Serrano". Small linking words ("de", "del", "la", "las", "los", "y", "e") stay in lower case unless
// they open the name ("De la Cruz"). A capital also follows a hyphen, an apostrophe or a dot ("Ana-Laura", "D'Angelo", "J.P.").
// Known limit: names with an inner capital ("McDonald") become "Mcdonald"; the person can fix it and an administrator can edit it.
// Los nombres de personas se guardan con mayúscula solo al comienzo de cada nombre: "LILIANA GARCIA SERRANO" o "liliana garcia
// serrano" -> "Liliana Garcia Serrano". Las palabras de enlace ("de", "del", "la", "las", "los", "y", "e") quedan en minúscula salvo
// que abran el nombre ("De la Cruz"). También va mayúscula después de guion, apóstrofo o punto. Límite conocido: un nombre con
// mayúscula interna ("McDonald") queda "Mcdonald".

const LINK_WORDS = new Set(["de", "del", "la", "las", "los", "y", "e"]);

export function titleCaseName(value: string): string {
  const words = value.replace(/\s+/g, " ").trim().split(" ");
  return words
    .map((word, index) => {
      const lower = word.toLocaleLowerCase("es");
      if (index > 0 && LINK_WORDS.has(lower)) return lower;
      return lower.replace(/(^|[-'’.])(\p{L})/gu, (_match, separator: string, letter: string) => separator + letter.toLocaleUpperCase("es"));
    })
    .join(" ");
}
