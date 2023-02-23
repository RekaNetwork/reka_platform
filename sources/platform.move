module rekanetwork::platform {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_std::table::{Self, Table};
    use aptos_std::type_info::{Self, TypeInfo};
    use aptos_token::token;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use aptos_framework::coin;

    struct RekaPlatform has key {
        ask_questions: Table<address, QuestionData>,
        collect_answers: Table<u64, vector<address>>,
        ask_questions_events: EventHandle<AskQuestionEvent>,
        answer_events: EventHandle<AnswerEvent>,
        favorite_events: EventHandle<FavoriteEvent>,
        collect_events: EventHandle<CollectAnswerEvent>
    }

    struct QuestionData has store, copy {
        creator: address,
        seed: vector<u8>,
        title: String,
        topic: String,
        describe: String,
        image: String,
        threshold: bool,
        collection_creator: address,
        collection_name: vector<u8>,
        coin_type: TypeInfo,
        coin_value: u64,
        answer_ids: vector<u64>,
        total_answer: u64,
        favorite_ids: vector<address>,
        total_favorite: u64
    }

    struct AskQuestionEvent has store, drop {
        ask_question_id: address,
        creator: address,
        create_timestamp: u64
    }

    struct AnswerEvent has store, drop {
        ask_question_id: address,
        answer_id: u64,
        creator: address,
        create_timestamp: u64
    }

    struct FavoriteEvent has store, drop {
        ask_question_id: address,
        favorite_flag: bool,
        creator: address,
        create_timestamp: u64
    }

    struct CollectAnswerEvent has store, drop {
        ask_question_id: address,
        answer_id: u64,
        collect_flag: bool,
        creator: address,
        create_timestamp: u64
    }

    const ECOLLECTION_NOT_EXIST: u64 = 0;
    const EASK_QUESTION_EXISTS: u64 = 1;
    const EASK_QUESTION_NOT_FOUND: u64 = 2;
    const EANSWER_COIN_VALUE: u64 = 3;
    const EANSWER_ID_EXISTS: u64 = 4;
    const EANSWER_ID_NOT_FOUND: u64 = 5;
    const ECOLLECT_ANSWER_ID: u64 = 6;

    fun init_module(signer: &signer) {
        move_to(signer, RekaPlatform {
            ask_questions: table::new<address, QuestionData>(),
            collect_answers: table::new<u64, vector<address>>(),
            ask_questions_events: account::new_event_handle<AskQuestionEvent>(signer),
            answer_events: account::new_event_handle<AnswerEvent>(signer),
            favorite_events: account::new_event_handle<FavoriteEvent>(signer),
            collect_events: account::new_event_handle<CollectAnswerEvent>(signer)
        });
    }

    public entry fun ask_question<CoinType>(
        account: &signer,
        seed: vector<u8>,
        title: vector<u8>,
        topic: vector<u8>,
        describe: vector<u8>,
        image: vector<u8>,
        threshold: bool,
        collection_creator: address,
        collection_name: vector<u8>,
        coin_value: u64
    ) acquires RekaPlatform {
        let creator_addr = signer::address_of(account);
        let ask_question_id = account::create_resource_address(&creator_addr, seed);

        let reka_platform = borrow_global_mut<RekaPlatform>(@rekanetwork);
        assert!(!table::contains(&reka_platform.ask_questions, ask_question_id), error::already_exists(EASK_QUESTION_EXISTS));

        if(threshold) {
            let name = string::utf8(collection_name);
            assert!(token::check_collection_exists(collection_creator, name), error::not_found(ECOLLECTION_NOT_EXIST));
        };
        let coin_type = type_info::type_of<CoinType>();
        table::add(&mut reka_platform.ask_questions, ask_question_id, QuestionData {
            creator: creator_addr, seed, title: string::utf8(title), topic: string::utf8(topic),
            describe: string::utf8(describe), image: string::utf8(image), threshold,
            collection_creator, collection_name, coin_type, coin_value, answer_ids: vector::empty<u64>(),
            total_answer: 0, favorite_ids: vector::empty<address>(), total_favorite: 0
        });

        event::emit_event<AskQuestionEvent>(
            &mut reka_platform.ask_questions_events,
            AskQuestionEvent {
                ask_question_id,
                creator: creator_addr,
                create_timestamp: timestamp::now_seconds()
            }
        );
    }

    public entry fun answer<CoinType>(account: &signer, ask_question_id: address, answer_id: u64) acquires RekaPlatform {
        let creator_addr = signer::address_of(account);

        let reka_platform = borrow_global_mut<RekaPlatform>(@rekanetwork);
        assert!(table::contains(&reka_platform.ask_questions, ask_question_id), error::not_found(EASK_QUESTION_NOT_FOUND));

        let question_data = table::borrow_mut(&mut reka_platform.ask_questions, ask_question_id);
        assert!(!vector::contains(&question_data.answer_ids, &answer_id), error::already_exists(EANSWER_ID_EXISTS));

        if(question_data.threshold) {
            assert!(question_data.coin_value > coin::balance<CoinType>(creator_addr), error::aborted(EANSWER_COIN_VALUE));
        };

        vector::push_back(&mut question_data.answer_ids, answer_id);
        question_data.total_answer = question_data.total_answer + 1;

        event::emit_event<AnswerEvent>(
            &mut reka_platform.answer_events,
            AnswerEvent {
                ask_question_id,
                answer_id,
                creator: creator_addr,
                create_timestamp: timestamp::now_seconds()
            }
        );
    }

    public entry fun favorite(account: &signer, ask_question_id: address, favorite_flag: bool) acquires RekaPlatform {
        let creator_addr = signer::address_of(account);

        let reka_platform = borrow_global_mut<RekaPlatform>(@rekanetwork);
        assert!(table::contains(&reka_platform.ask_questions, ask_question_id), error::not_found(EASK_QUESTION_NOT_FOUND));

        let question_data = table::borrow_mut(&mut reka_platform.ask_questions, ask_question_id);
        if(favorite_flag) {
            assert!(!vector::contains(&question_data.favorite_ids, &creator_addr), error::already_exists(EANSWER_ID_EXISTS));
            vector::push_back(&mut question_data.favorite_ids, creator_addr);
            question_data.total_favorite = question_data.total_favorite + 1;
        }else {
            assert!(vector::contains(&question_data.favorite_ids, &creator_addr), error::already_exists(EANSWER_ID_EXISTS));
            let (item, index) = vector::index_of(&question_data.favorite_ids, &creator_addr);
            if(item) {
                vector::remove(&mut question_data.favorite_ids, index);
                question_data.total_favorite = question_data.total_favorite - 1;
            }
        };

        event::emit_event<FavoriteEvent>(
            &mut reka_platform.favorite_events,
            FavoriteEvent {
                ask_question_id,
                favorite_flag,
                creator: creator_addr,
                create_timestamp: timestamp::now_seconds()
            }
        );
    }

    public entry fun collect(account: &signer, ask_question_id: address, answer_id: u64, collect_flag: bool) acquires RekaPlatform {
        let creator_addr = signer::address_of(account);

        let reka_platform = borrow_global_mut<RekaPlatform>(@rekanetwork);
        assert!(table::contains(&reka_platform.ask_questions, ask_question_id), error::not_found(EASK_QUESTION_NOT_FOUND));

        let question_data = table::borrow_mut(&mut reka_platform.ask_questions, ask_question_id);
        assert!(vector::contains(&question_data.answer_ids, &answer_id), error::not_found(EANSWER_ID_NOT_FOUND));

        let collect_answers = table::borrow_mut(&mut reka_platform.collect_answers, answer_id);
        if(collect_flag) {
            assert!(!vector::contains(collect_answers, &creator_addr), error::already_exists(ECOLLECT_ANSWER_ID));
            vector::push_back(collect_answers, creator_addr);
        }else {
            assert!(vector::contains(collect_answers, &creator_addr), error::already_exists(ECOLLECT_ANSWER_ID));
            let (item, index) = vector::index_of(collect_answers, &creator_addr);
            if(item) {
                vector::remove(collect_answers, index);
            }
        };

        event::emit_event<CollectAnswerEvent>(
            &mut reka_platform.collect_events,
            CollectAnswerEvent {
                ask_question_id,
                answer_id,
                collect_flag,
                creator: creator_addr,
                create_timestamp: timestamp::now_seconds()
            }
        );
    }
}
