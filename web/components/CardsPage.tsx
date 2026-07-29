"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { api, Card, Subject, Tag } from "@/lib/api";

export default function CardsPage() {
  const [subjects, setSubjects] = useState<Subject[]>([]);
  const [tags, setTags] = useState<Tag[]>([]);
  const [cards, setCards] = useState<Card[]>([]);
  const [subjectID, setSubjectID] = useState("");
  const [tagID, setTagID] = useState("");
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    api
      .listSubjects()
      .then(setSubjects)
      .catch((err: Error) => setError(err.message));
  }, []);

  useEffect(() => {
    if (!subjectID) {
      setTags([]);
      setTagID("");
      return;
    }
    api
      .listTags(subjectID)
      .then(setTags)
      .catch((err: Error) => setError(err.message));
  }, [subjectID]);

  useEffect(() => {
    setLoading(true);
    api
      .listCards({
        subject_id: subjectID || undefined,
        tag_ids: tagID ? [tagID] : undefined,
        search: search || undefined
      })
      .then(setCards)
      .catch((err: Error) => setError(err.message))
      .finally(() => setLoading(false));
  }, [subjectID, tagID, search]);

  const selectedSubject = useMemo(
    () => subjects.find((subject) => subject.id === subjectID),
    [subjects, subjectID]
  );
  const totalCards = subjects.reduce((total, subject) => total + subject.card_count, 0);
  const dueCount = subjects.reduce((total, subject) => total + subject.due_count, 0);

  async function deleteCard(cardID: string) {
    if (!confirm("Delete this study set?")) {
      return;
    }
    await api.deleteCard(cardID);
    setCards((current) => current.filter((card) => card.id !== cardID));
  }

  return (
    <section>
      <div className="pageHero">
        <div>
          <p className="eyebrow">Library</p>
          <h1>Your English study sets</h1>
          <p className="subtle">
            Build focused sets for the iOS review app, then keep cards organized by subject and tag.
          </p>
        </div>
        <div className="heroCard">
          <div className="heroMetric">
            <div className="metric">
              <strong>{subjects.length}</strong>
              <span>subjects</span>
            </div>
            <div className="metric">
              <strong>{totalCards}</strong>
              <span>cards</span>
            </div>
            <div className="metric">
              <strong>{dueCount}</strong>
              <span>due</span>
            </div>
          </div>
        </div>
      </div>

      {error && <div className="error">{error}</div>}

      <div className="toolbar">
        <div className="field">
          <label htmlFor="search">Search</label>
          <input
            id="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search front or answer"
          />
        </div>
        <div className="field">
          <label htmlFor="subject">Subject</label>
          <select id="subject" value={subjectID} onChange={(event) => setSubjectID(event.target.value)}>
            <option value="">All subjects</option>
            {subjects.map((subject) => (
              <option key={subject.id} value={subject.id}>
                {subject.name}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="tag">Tag</label>
          <select
            id="tag"
            value={tagID}
            onChange={(event) => setTagID(event.target.value)}
            disabled={!selectedSubject}
          >
            <option value="">All tags</option>
            {tags.map((tag) => (
              <option key={tag.id} value={tag.id}>
                {tag.name}
              </option>
            ))}
          </select>
        </div>
        <button
          className="secondary"
          onClick={() => {
            setSubjectID("");
            setTagID("");
            setSearch("");
          }}
        >
          Reset
        </button>
      </div>

      <div className="setGrid">
        {cards.map((card) => (
          <article className="setCard" key={card.id}>
            <div className="setTopline">
              <div className="setTitle">
                <div className="setMeta">
                  <span className="pill">{card.subject_name}</span>
                  <span className="pill pillMuted">{card.answer_tokens.length} terms</span>
                </div>
                <h3>{card.front_text}</h3>
              </div>
            </div>

            <div className="termPreview">
              <div className="termBlock">
                <span>Answer</span>
                <p>{card.answer_text}</p>
              </div>
              {card.grammar_phrases.length > 0 && (
                <div className="termBlock">
                  <span>Key phrase</span>
                  <p>{card.grammar_phrases[0].text}</p>
                </div>
              )}
            </div>

            <div className="setMeta">
              {card.tags.length > 0 ? (
                <div className="tagList">
                  {card.tags.map((tag) => (
                    <span className="tag" key={tag.id}>
                      {tag.name}
                    </span>
                  ))}
                </div>
              ) : (
                <span className="pill pillMuted">No tags</span>
              )}
            </div>

            <div className="setFooter">
              <span className="subtle">Updated {new Date(card.updated_at).toLocaleDateString()}</span>
              <div className="actions">
                <Link className="secondary" href={`/cards/${card.id}/edit`}>
                  Edit
                </Link>
                <button className="danger" onClick={() => deleteCard(card.id)}>
                  Delete
                </button>
              </div>
            </div>
          </article>
        ))}
      </div>

      {!loading && cards.length === 0 && (
        <div className="empty">
          No study sets found.
          <div className="emptyAction">
            <Link className="primaryButton" href="/cards/new">
              Create a set
            </Link>
          </div>
        </div>
      )}

      {loading && <div className="empty">Loading study sets...</div>}

      {cards.length > 0 && (
        <div className="sectionAction">
          <Link className="primaryButton" href="/cards/new">
            Create a new set
          </Link>
        </div>
      )}
    </section>
  );
}
