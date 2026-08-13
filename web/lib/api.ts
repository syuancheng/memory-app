export type Subject = {
  id: string;
  name: string;
  card_count: number;
  due_count: number;
};

export type Set = {
  id: string;
  subject_id: string;
  name: string;
  card_count: number;
  due_count: number;
};

export type GrammarPhrase = {
  text: string;
  note: string;
};

export type AnswerToken = {
  text: string;
  index: number;
};

export type Card = {
  id: string;
  subject_id: string;
  subject_name?: string;
  set_id: string;
  set: Set;
  card_type: string;
  direction: string;
  front_text: string;
  answer_text: string;
  grammar_phrases: GrammarPhrase[];
  answer_tokens: AnswerToken[];
  created_at: string;
  updated_at: string;
};

export type CardPayload = {
  set_id: string;
  card_type: string;
  direction: string;
  front_text: string;
  answer_text: string;
  grammar_phrases: GrammarPhrase[];
};

export type AuthUser = {
  id: string;
  email: string;
  name: string;
};

export type AuthResponse = {
  user: AuthUser;
  session_token?: string;
};

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8080/api";
const TOKEN_KEY = "cardly_session_token";

export const sessionToken = {
  get: () => {
    if (typeof window === "undefined") {
      return "";
    }
    return window.localStorage.getItem(TOKEN_KEY) ?? "";
  },
  set: (token: string) => {
    if (typeof window !== "undefined") {
      window.localStorage.setItem(TOKEN_KEY, token);
    }
  },
  clear: () => {
    if (typeof window !== "undefined") {
      window.localStorage.removeItem(TOKEN_KEY);
    }
  }
};

async function request<T>(path: string, init?: RequestInit & { auth?: boolean }): Promise<T> {
  const token = init?.auth === false ? "" : sessionToken.get();
  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(init?.headers ?? {})
    },
    cache: "no-store"
  });

  if (response.status === 401) {
    sessionToken.clear();
    throw new Error("Please sign in again.");
  }

  if (!response.ok) {
    let message = `Request failed: ${response.status}`;
    try {
      const body = (await response.json()) as { error?: string };
      if (body.error) {
        message = body.error;
      }
    } catch {
      // Keep the status-based message.
    }
    throw new Error(message);
  }

  return response.json() as Promise<T>;
}

export const api = {
  requestAuthCode: (email: string) =>
    request<{ status: string }>("/auth/request-code", {
      method: "POST",
      auth: false,
      body: JSON.stringify({ email })
    }),
  verifyAuthCode: (email: string, code: string) =>
    request<AuthResponse>("/auth/verify-code", {
      method: "POST",
      auth: false,
      body: JSON.stringify({ email, code })
    }),
  getCurrentUser: () => request<AuthResponse>("/auth/me"),
  logout: () =>
    request<{ status: string }>("/auth/logout", {
      method: "POST"
    }),
  listSubjects: () => request<Subject[]>("/subjects"),
  createSubject: (name: string) =>
    request<Subject>("/subjects", {
      method: "POST",
      body: JSON.stringify({ name })
    }),
  listSets: (subjectID: string) => request<Set[]>(`/subjects/${subjectID}/sets`),
  createSet: (subjectID: string, name: string) =>
    request<Set>(`/subjects/${subjectID}/sets`, {
      method: "POST",
      body: JSON.stringify({ name })
    }),
  listCards: (params: { subject_id?: string; set_ids?: string[]; search?: string } = {}) => {
    const search = new URLSearchParams();
    if (params.subject_id) {
      search.set("subject_id", params.subject_id);
    }
    if (params.set_ids && params.set_ids.length > 0) {
      search.set("set_ids", params.set_ids.join(","));
    }
    if (params.search) {
      search.set("search", params.search);
    }
    const suffix = search.toString() ? `?${search.toString()}` : "";
    return request<Card[]>(`/cards${suffix}`);
  },
  getCard: (cardID: string) => request<Card>(`/cards/${cardID}`),
  createCard: (payload: CardPayload) =>
    request<Card>("/cards", {
      method: "POST",
      body: JSON.stringify(payload)
    }),
  updateCard: (cardID: string, payload: CardPayload) =>
    request<Card>(`/cards/${cardID}`, {
      method: "PUT",
      body: JSON.stringify(payload)
    }),
  deleteCard: (cardID: string) =>
    request<{ status: string }>(`/cards/${cardID}`, {
      method: "DELETE"
    })
};
